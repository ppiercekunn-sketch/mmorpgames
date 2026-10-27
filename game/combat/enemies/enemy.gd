class_name Enemy
extends Actor
## A hostile mob driven by the EnemyAI state machine (IDLE / CHASE / ATTACK /
## LEASH). Built from a data/enemies.json entry via configure() before it is
## added to the tree (EnemySpawner does this).
##
## Clicking it (ClickArea, an input-pickable Area2D) makes it the player's
## target. Progression can read `enemy_id`, `get_xp_reward()` and
## `get_loot_table()` (the id is also stored as meta "enemy_id").

## Emitted after the death fade, right before queue_free().
signal despawned

## Click/hover radius around the body centre, in pixels.
const CLICK_RADIUS := 22.0
## Body centre relative to the feet (the node origin), before scaling.
const BODY_OFFSET := Vector2(0, -14)
const WANDER_RADIUS := 50.0
const DEATH_FADE_TIME := 0.8
## Re-path towards the player only when they moved this far.
const REPATH_DISTANCE := 12.0

var enemy_id: String = ""
var enemy_data: Dictionary = {}
var home_position: Vector2 = Vector2.ZERO
var state: EnemyAI.State = EnemyAI.State.IDLE
var aggro_radius: float = 150.0
var leash_radius: float = 400.0
var attack_range: float = 40.0
var attack_cooldown: float = 1.5
var body_color: Color = Color.WHITE
var body_kind: String = "blob"
var body_scale: float = 1.0

var _rng := RandomNumberGenerator.new()
var _attack_timer: float = 0.0
var _wander_timer: float = 0.0
var _hit_flash: float = 0.0
var _facing: float = 1.0
var _hovered: bool = false
var _targeted: bool = false
var _last_chase_pos: Vector2 = Vector2.INF

@onready var _click_area: Area2D = get_node_or_null("ClickArea")
@onready var _body_shape: CollisionShape2D = get_node_or_null("CollisionShape2D")


## Applies an enemies.json entry. Call before adding the enemy to the tree.
func configure(id: String, data: Dictionary) -> void:
	enemy_id = id
	enemy_data = data
	set_meta("enemy_id", id)
	display_name = str(data.get("name", id))
	team = Team.ENEMY
	stats = EnemyAI.build_stats(data)
	aggro_radius = float(data.get("aggro_radius", aggro_radius))
	leash_radius = float(data.get("leash_radius", leash_radius))
	attack_range = float(data.get("attack_range", attack_range))
	attack_cooldown = float(data.get("attack_cooldown", attack_cooldown))
	body_color = Color.from_string(str(data.get("color", "#ffffff")), Color.WHITE)
	body_kind = str(data.get("body", "blob"))
	body_scale = float(data.get("scale", 1.0))


func _ready() -> void:
	team = Team.ENEMY
	add_to_group("enemies")
	super._ready()
	home_position = global_position
	_rng.randomize()
	_wander_timer = _rng.randf_range(1.0, 4.0)
	# Area2D clicks need physics picking; harmless if the world already enabled it.
	get_viewport().physics_object_picking = true
	if _click_area:
		_click_area.position = BODY_OFFSET * body_scale
		_click_area.scale = Vector2.ONE * body_scale
		_click_area.input_event.connect(_on_click_area_input_event)
		_click_area.mouse_entered.connect(_set_hovered.bind(true))
		_click_area.mouse_exited.connect(_set_hovered.bind(false))
	Events.target_changed.connect(_on_target_changed)


func get_xp_reward() -> int:
	return int(enemy_data.get("xp", 0))


func get_loot_table() -> String:
	return str(enemy_data.get("loot_table", ""))


## True if a click at `world_pos` lands on this enemy's body.
func contains_point(world_pos: Vector2) -> bool:
	return click_distance(world_pos) <= CLICK_RADIUS * body_scale


func click_distance(world_pos: Vector2) -> float:
	return world_pos.distance_to(global_position + BODY_OFFSET * body_scale)


func take_damage(amount: int, source: Node = null, is_crit: bool = false) -> void:
	super.take_damage(amount, source, is_crit)
	if is_dead:
		return
	_hit_flash = 0.15
	# Getting hit while idle provokes the enemy even outside its aggro radius.
	if state == EnemyAI.State.IDLE and source is Actor and is_hostile_to(source as Actor):
		_enter_state(EnemyAI.State.CHASE)


func die(killer: Node = null) -> void:
	if is_dead:
		return
	super.die(killer)
	remove_from_group("enemies")
	if _body_shape:
		_body_shape.set_deferred("disabled", true)
	if _click_area:
		_click_area.input_pickable = false
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, DEATH_FADE_TIME)
	tween.tween_callback(_despawn)


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	var player := _find_player()
	var has_player := player != null and not player.is_dead
	var player_pos := player.global_position if player else Vector2.ZERO
	var next_state := EnemyAI.decide(
		state,
		global_position,
		home_position,
		player_pos,
		has_player,
		aggro_radius,
		leash_radius,
		attack_range
	)
	if next_state != state:
		_enter_state(next_state)
	match state:
		EnemyAI.State.IDLE:
			_tick_idle(delta)
		EnemyAI.State.CHASE:
			_tick_chase(player_pos)
		EnemyAI.State.ATTACK:
			_tick_attack(player)
	super._physics_process(delta)
	if velocity.x != 0.0:
		_facing = signf(velocity.x)
	queue_redraw()


func _enter_state(new_state: EnemyAI.State) -> void:
	var old_state := state
	state = new_state
	_last_chase_pos = Vector2.INF
	match new_state:
		EnemyAI.State.IDLE:
			stop_moving()
			_wander_timer = _rng.randf_range(2.0, 5.0)
			if old_state == EnemyAI.State.LEASH:
				heal(stats.max_hp() - hp, self)
		EnemyAI.State.ATTACK:
			stop_moving()
			# Short wind-up so the first hit isn't instant.
			_attack_timer = maxf(_attack_timer, 0.4)
		EnemyAI.State.LEASH:
			move_to(home_position)


func _tick_idle(delta: float) -> void:
	if is_moving():
		return
	_wander_timer -= delta
	if _wander_timer > 0.0:
		return
	_wander_timer = _rng.randf_range(2.0, 5.0)
	var offset := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(10.0, WANDER_RADIUS)
	move_to(home_position + offset)


func _tick_chase(player_pos: Vector2) -> void:
	if not is_moving() or player_pos.distance_to(_last_chase_pos) > REPATH_DISTANCE:
		_last_chase_pos = player_pos
		move_to(player_pos)


func _tick_attack(player: Actor) -> void:
	stop_moving()
	if player == null:
		return
	_facing = signf(player.global_position.x - global_position.x)
	if _facing == 0.0:
		_facing = 1.0
	if _attack_timer > 0.0:
		return
	_attack_timer = attack_cooldown
	var result := CombatRules.roll_damage(stats, player.stats, 1.0, _rng)
	player.take_damage(result.amount, self, result.is_crit)


func _find_player() -> Actor:
	return get_tree().get_first_node_in_group("player") as Actor


func _select_as_target() -> void:
	var player := _find_player() as Player
	if player:
		player.set_target(self, true)


func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if is_dead:
		return
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_select_as_target()
		get_viewport().set_input_as_handled()


func _set_hovered(value: bool) -> void:
	_hovered = value
	queue_redraw()


func _on_target_changed(new_target: Node) -> void:
	_targeted = new_target == self
	queue_redraw()


func _despawn() -> void:
	despawned.emit()
	queue_free()


# --- Placeholder art -------------------------------------------------------


func _draw() -> void:
	var s := body_scale
	var center := BODY_OFFSET * s
	# Shadow
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 14.0 * s, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _targeted or _hovered:
		var ring_color := Color(1, 0.3, 0.3) if _targeted else Color(1, 1, 1, 0.6)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, 20.0 * s, 0.0, TAU, 32, ring_color, 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var color := body_color.lightened(0.6) if _hit_flash > 0.0 else body_color
	match body_kind:
		"beast":
			_draw_beast(center, s, color)
		"humanoid":
			_draw_humanoid(center, s, color)
		_:
			_draw_blob(center, s, color)
	_draw_hp_bar(center + Vector2(0, -22.0 * s))


func _draw_blob(center: Vector2, s: float, color: Color) -> void:
	draw_circle(center + Vector2(0, 4) * s, 13.0 * s, color)
	draw_circle(center + Vector2(-4 * _facing, 0) * s, 2.0 * s, Color.BLACK)
	draw_circle(center + Vector2(4 * _facing, 0) * s, 2.0 * s, Color.BLACK)


func _draw_beast(center: Vector2, s: float, color: Color) -> void:
	draw_rect(Rect2(center + Vector2(-14, -6) * s, Vector2(28, 14) * s), color)
	draw_circle(center + Vector2(14 * _facing, -6) * s, 7.0 * s, color)
	draw_circle(center + Vector2(17 * _facing, -8) * s, 1.5 * s, Color.BLACK)
	for x: float in [-10.0, -4.0, 4.0, 10.0]:
		draw_line(center + Vector2(x, 8) * s, center + Vector2(x, 14) * s, color.darkened(0.3), 3.0)


func _draw_humanoid(center: Vector2, s: float, color: Color) -> void:
	draw_rect(Rect2(center + Vector2(-8, -6) * s, Vector2(16, 20) * s), color)
	draw_circle(center + Vector2(0, -12) * s, 7.0 * s, Color(0.95, 0.8, 0.65))
	draw_rect(Rect2(center + Vector2(-8, -18) * s, Vector2(16, 4) * s), color.darkened(0.4))
	draw_line(
		center + Vector2(10 * _facing, 0) * s,
		center + Vector2(20 * _facing, -12) * s,
		Color(0.8, 0.8, 0.85),
		2.0
	)


func _draw_hp_bar(bar_center: Vector2) -> void:
	var width := 34.0
	var ratio := float(hp) / float(maxi(stats.max_hp(), 1))
	var origin := bar_center - Vector2(width / 2.0, 0)
	draw_rect(Rect2(origin - Vector2(1, 1), Vector2(width + 2, 6)), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(origin, Vector2(width * ratio, 4)), Color(0.85, 0.2, 0.2))
	var font := ThemeDB.fallback_font
	var label := "Lv%d %s" % [stats.level, display_name]
	draw_string(
		font,
		origin + Vector2(-20, -4),
		label,
		HORIZONTAL_ALIGNMENT_CENTER,
		width + 40,
		10,
		Color.WHITE
	)
