class_name Pet
extends Actor
## Starter pet. Follows its owner, fights the owner's target, defends the owner,
## earns a share of XP and respawns next to the owner after dying.
## Created by Progression: instance pet.tscn, call setup(), then add it to the
## entities root. Has a "NavAgent" child; falls back to straight-line movement
## when the world has no navigation regions (e.g. the progression sandbox).

signal leveled_up(new_level: int)
signal respawned()

const FOLLOW_OFFSET := Vector2(-30.0, 14.0)
## Start following when this far from the follow spot; stop when close again.
const FOLLOW_SLACK := 36.0
const FOLLOW_STOP := 6.0
const TELEPORT_DISTANCE := 520.0
## Give up a target that drags the pet this far from its owner.
const LEASH_DISTANCE := 420.0
const ATTACK_ANIM_TIME := 0.2
const BODY_RADIUS := 9.0
const PETS_LAYER := 1 << 3
const WORLD_LAYER := 1
## Default on-screen height of the CharacterArt image (pets.json "sprite_height").
const DEFAULT_SPRITE_HEIGHT := 34.0

var pet_id: String = ""
var pet_def: Dictionary = {}
var owner_actor: Actor
var leveling: Leveling
var target: Actor
var attack_range: float = 40.0
var attack_interval: float = 1.4
var respawn_seconds: float = 10.0
var xp_share: float = 0.5

var _rng := RandomNumberGenerator.new()
var _attack_cooldown: float = 0.0
var _attack_anim: float = 0.0
var _facing: float = 1.0
var _following: bool = false
var _nav_check_timer: float = 0.0
var _nav_ready: bool = false
var _body_color := Color(1.0, 0.82, 0.4)
var _shape: CollisionShape2D
## Image-based body (null = draw the placeholder shapes).
var _art: CharacterSprite


## Call before adding the pet to the tree (or any time to re-level it).
func setup(
	owner_node: Actor, id: String, def: Dictionary, xp_curve: Dictionary,
	start_level: int = 1, start_xp: int = 0
) -> void:
	owner_actor = owner_node
	pet_id = id
	pet_def = def
	leveling = Leveling.new(xp_curve, start_level, start_xp)
	display_name = str(def.get("name", "Pet"))
	team = Team.PLAYER
	attack_range = float(def.get("attack_range", attack_range))
	attack_interval = float(def.get("attack_interval", attack_interval))
	respawn_seconds = float(def.get("respawn_seconds", respawn_seconds))
	xp_share = float(def.get("xp_share", xp_share))
	_body_color = Color.from_string(str(def.get("color", "#ffd166")), _body_color)
	stats = PetRules.build_stats(def, leveling.level)
	if is_inside_tree():
		_refill()


func _ready() -> void:
	super._ready()
	add_to_group("pets")
	team = Team.PLAYER
	collision_layer = PETS_LAYER
	collision_mask = WORLD_LAYER
	_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 7.0
	_shape.shape = circle
	add_child(_shape)
	var art_height := float(pet_def.get("sprite_height", DEFAULT_SPRITE_HEIGHT))
	_art = CharacterSprite.try_attach(self, pet_id, art_height)
	_rng.randomize()
	Events.target_changed.connect(_on_target_changed)
	Events.actor_damaged.connect(_on_actor_damaged)
	Events.actor_died.connect(_on_actor_died)
	died.connect(_on_self_died)
	hp_changed.connect(_on_hp_changed)


func get_level() -> int:
	return leveling.level if leveling else stats.level


## Adds XP; returns levels gained. Stats grow per pets.json "growth" on level up.
func add_xp(amount: int) -> int:
	if leveling == null or amount <= 0 or is_dead:
		return 0
	var gained := leveling.add_xp(amount)
	Events.xp_gained.emit(self, amount)
	if gained > 0:
		stats = PetRules.build_stats(pet_def, leveling.level)
		_refill()
		Events.level_up.emit(self, leveling.level)
		leveled_up.emit(leveling.level)
	return gained


func set_target(new_target: Actor) -> void:
	if new_target == null or new_target == self or not is_hostile_to(new_target):
		return
	target = new_target


func teleport_to_owner() -> void:
	if not is_instance_valid(owner_actor):
		return
	global_position = owner_actor.global_position + FOLLOW_OFFSET
	velocity = Vector2.ZERO
	target = null
	_following = false
	if nav_agent:
		nav_agent.target_position = global_position


func _physics_process(delta: float) -> void:
	# Movement is handled here instead of Actor's move_to() so following a
	# moving owner does not restart a path every frame.
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_attack_anim = maxf(_attack_anim - delta, 0.0)
	_nav_check_timer -= delta
	queue_redraw()
	if is_dead or not is_instance_valid(owner_actor):
		return
	if global_position.distance_to(owner_actor.global_position) > TELEPORT_DISTANCE:
		teleport_to_owner()
		return
	if not _target_is_valid():
		target = null
	if target:
		_fight()
	else:
		_follow()


func _fight() -> void:
	var to_target := target.global_position - global_position
	if absf(to_target.x) > 1.0:
		_facing = signf(to_target.x)
	if to_target.length() > attack_range:
		_steer_towards(target.global_position)
		return
	velocity = Vector2.ZERO
	if _attack_cooldown <= 0.0:
		_attack()


func _attack() -> void:
	var target_defense := 0
	if target.stats:
		target_defense = target.stats.defense()
	var hit := PetRules.damage(stats.attack(), target_defense, stats.crit_chance(), _rng)
	_attack_cooldown = attack_interval
	_attack_anim = ATTACK_ANIM_TIME
	if _art:
		_art.play_attack(_facing)
	target.take_damage(int(hit["amount"]), self, bool(hit["crit"]))


func _follow() -> void:
	var spot := owner_actor.global_position + Vector2(FOLLOW_OFFSET.x, FOLLOW_OFFSET.y)
	var dist := global_position.distance_to(spot)
	if dist > FOLLOW_SLACK or (_following and dist > FOLLOW_STOP):
		_following = true
		_steer_towards(spot)
	else:
		_following = false
		velocity = Vector2.ZERO


func _steer_towards(point: Vector2) -> void:
	var next_point := point
	if _navigation_available():
		if nav_agent.target_position.distance_to(point) > 8.0:
			nav_agent.target_position = point
		if not nav_agent.is_navigation_finished():
			next_point = nav_agent.get_next_path_position()
	velocity = global_position.direction_to(next_point) * stats.move_speed()
	move_and_slide()
	if absf(velocity.x) > 1.0:
		_facing = signf(velocity.x)


func _navigation_available() -> bool:
	if nav_agent == null:
		return false
	if _nav_check_timer <= 0.0:
		_nav_check_timer = 1.0
		var map := get_world_2d().navigation_map
		_nav_ready = map.is_valid() and not NavigationServer2D.map_get_regions(map).is_empty()
	return _nav_ready


func _target_is_valid() -> bool:
	if target == null or not is_instance_valid(target) or target.is_dead:
		return false
	if not is_instance_valid(owner_actor):
		return false
	var owner_pos := owner_actor.global_position
	return target.global_position.distance_to(owner_pos) <= LEASH_DISTANCE


func _refill() -> void:
	hp = stats.max_hp()
	mp = stats.max_mp()
	hp_changed.emit(hp, stats.max_hp())
	mp_changed.emit(mp, stats.max_mp())


func _respawn() -> void:
	if not is_inside_tree():
		return
	is_dead = false
	_refill()
	teleport_to_owner()
	if _shape:
		_shape.set_deferred("disabled", false)
	respawned.emit()


func _on_self_died(_killer: Node) -> void:
	target = null
	velocity = Vector2.ZERO
	if _shape:
		_shape.set_deferred("disabled", true)
	get_tree().create_timer(respawn_seconds).timeout.connect(_respawn)


func _on_target_changed(new_target: Node) -> void:
	if is_dead or not is_instance_valid(new_target) or not (new_target is Actor):
		return
	var enemy := new_target as Actor
	if enemy.is_in_group("enemies") and not enemy.is_dead:
		set_target(enemy)


## Defend: an enemy that hits the owner (or the pet) becomes the target
## when the pet is not already fighting something.
func _on_actor_damaged(victim: Node, _amount: int, source: Node, _is_crit: bool) -> void:
	if is_dead or (victim != owner_actor and victim != self):
		return
	if _target_is_valid() or not is_instance_valid(source) or not (source is Actor):
		return
	var attacker := source as Actor
	if attacker.is_in_group("enemies") and not attacker.is_dead:
		set_target(attacker)


func _on_actor_died(actor: Node, _killer: Node) -> void:
	if actor == target:
		target = null


func _on_hp_changed(_current: int, _maximum: int) -> void:
	queue_redraw()


func _draw() -> void:
	var alpha := 0.3 if is_dead else 1.0
	var lunge := Vector2(_facing * 7.0 * (_attack_anim / ATTACK_ANIM_TIME), 0.0)
	if _art:
		_draw_overlay(alpha, minf(0.0, 25.0 - _art.height))
		return
	# Shadow
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 11.0, Color(0, 0, 0, 0.3 * alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Body, ears, eye, star mark
	var col := _body_color
	col.a = alpha
	var c := Vector2(0.0, -10.0) + lunge
	draw_circle(c, BODY_RADIUS, col)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-8, -4), c + Vector2(-5, -15), c + Vector2(-1, -8)]), col)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(8, -4), c + Vector2(5, -15), c + Vector2(1, -8)]), col)
	draw_circle(c + Vector2(_facing * 4.0, -2.0), 1.7, Color(0.1, 0.1, 0.15, alpha))
	draw_circle(c + Vector2(-_facing * 2.0, -6.0), 1.5, Color(1, 1, 1, alpha))
	_draw_overlay(alpha, 0.0)


## Name, level and HP bar, raised by `lift` (negative = up) above a tall image.
func _draw_overlay(alpha: float, lift: float) -> void:
	var font := ThemeDB.fallback_font
	var label := "%s Lv%d" % [display_name, get_level()]
	draw_string_outline(font, Vector2(-50, -32 + lift), label, HORIZONTAL_ALIGNMENT_CENTER,
		100, 10, 3, Color(0, 0, 0, 0.8 * alpha))
	draw_string(font, Vector2(-50, -32 + lift), label, HORIZONTAL_ALIGNMENT_CENTER,
		100, 10, Color(1, 0.95, 0.7, alpha))
	if stats and not is_dead:
		var ratio := clampf(float(hp) / float(maxi(stats.max_hp(), 1)), 0.0, 1.0)
		draw_rect(Rect2(-14, -29 + lift, 28, 3), Color(0.15, 0.05, 0.05, 0.8))
		draw_rect(Rect2(-14, -29 + lift, 28 * ratio, 3), Color(0.4, 0.9, 0.4))
