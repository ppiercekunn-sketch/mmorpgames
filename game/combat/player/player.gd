class_name Player
extends Actor
## The local player (Warrior). Joins group "player".
##
## Input:
## - Events.ground_clicked: walk there, or target the enemy under the click.
## - Clicking an enemy (Enemy.ClickArea) calls set_target(enemy, true): the
##   player walks into range and auto-attacks.
## - Actions skill_1..skill_6 cast the hotbar skills (data/skills.json,
##   ordered by "slot") on the current target or around the player.
##
## The birth-sign passive is merged into stats.bonuses at spawn. Progression
## rebuilds the full bonuses dict later; it should start from
## get_base_bonuses() and add gear on top.

## Emitted when a cast is refused (reason is a SkillRules constant).
signal cast_failed(skill_id: String, reason: String)
signal skill_cast(skill_id: String)
signal respawned
signal buffs_changed

const AUTO_ATTACK_RANGE := 56.0
const AUTO_ATTACK_INTERVAL := 1.3
const AUTO_ATTACK_POWER := 1.0
## Seconds after the last hit dealt or taken before regeneration starts.
const OUT_OF_COMBAT_DELAY := 5.0
## Fraction of max MP / max HP regenerated per second out of combat.
const MP_REGEN_RATE := 0.025
const HP_REGEN_RATE := 0.02
const CHARGE_TIME := 0.18
## Charge stops this far from the target's centre.
const CHARGE_STOP_DISTANCE := 36.0
## Re-path towards the target only when it moved this far.
const REPATH_DISTANCE := 12.0
const HOTBAR_SIZE := 6

## Disable to ignore the NavAgent and walk in straight lines (sandbox, or any
## scene without a navigation map).
@export var use_navigation: bool = true
@export var respawn_delay: float = 4.0

var current_target: Actor = null
var spawn_point: Vector2 = Vector2.ZERO
var cooldowns := SkillCooldowns.new()

## skill_id -> skills.json entry
var _skills: Dictionary = {}
## Hotbar order, HOTBAR_SIZE entries ("" = empty slot).
var _slots: Array[String] = []
## effect ("buff_attack" / "buff_defense") -> {"amount": float, "remaining": float}
var _buffs: Dictionary = {}
var _rng := RandomNumberGenerator.new()
## True while the player should close in on and auto-attack current_target.
var _engaging: bool = false
## Targeted skill waiting for the player to walk into range.
var _pending_skill: String = ""
var _auto_attack_timer: float = 0.0
var _combat_timer: float = 0.0
var _hp_regen_acc: float = 0.0
var _mp_regen_acc: float = 0.0
var _charging: bool = false
var _last_chase_pos: Vector2 = Vector2.INF
var _facing: float = 1.0
var _swing_time: float = 0.0
var _ring_time: float = 0.0
var _ring_radius: float = 0.0
var _ring_color: Color = Color.WHITE


func _ready() -> void:
	team = Team.PLAYER
	add_to_group("player")
	if stats == null:
		stats = Stats.new()
	_apply_session_character()
	super._ready()
	if not use_navigation:
		nav_agent = null
	spawn_point = global_position
	_rng.randomize()
	_load_skills()
	Events.ground_clicked.connect(_on_ground_clicked)
	Events.actor_died.connect(_on_actor_died)
	died.connect(_on_died)


# --- Public API ---------------------------------------------------------------


## The birth-sign passive bonuses (zodiac_signs.json "passive"). Progression
## merges gear on top of this when it rebuilds stats.bonuses.
func get_base_bonuses() -> Dictionary:
	var sign_id := str(Session.character.get("birth_sign", ""))
	if sign_id == "":
		return {}
	var passive: Variant = GameData.get_entry("zodiac_signs", sign_id).get("passive", {})
	if passive is Dictionary:
		return (passive as Dictionary).duplicate()
	return {}


## Selects `target` (null clears). With `engage`, walk into range and attack.
func set_target(target: Actor, engage: bool = false) -> void:
	if target != null and (target.is_dead or not is_hostile_to(target)):
		target = null
	if target != current_target:
		current_target = target
		_pending_skill = ""
		Events.target_changed.emit(current_target)
	_engaging = engage and current_target != null and not is_dead
	_last_chase_pos = Vector2.INF


func clear_target() -> void:
	set_target(null)


func set_spawn_point(world_pos: Vector2) -> void:
	spawn_point = world_pos


## Hotbar skill ids in slot order (always HOTBAR_SIZE entries, "" = empty).
func get_skill_slots() -> Array[String]:
	return _slots


func get_skill(skill_id: String) -> Dictionary:
	return _skills.get(skill_id, {})


func is_skill_unlocked(skill_id: String) -> bool:
	var skill := get_skill(skill_id)
	return not skill.is_empty() and SkillRules.is_unlocked(skill, stats.level)


## Effect -> {"amount", "remaining"} of the buffs currently active.
func get_active_buffs() -> Dictionary:
	return _buffs


## Attack multiplier from active buffs (War Cry).
func get_attack_multiplier() -> float:
	return 1.0 + _buff_amount("buff_attack")


## Damage taken multiplier from active buffs (Shield Wall).
func get_damage_taken_multiplier() -> float:
	return clampf(1.0 - _buff_amount("buff_defense"), 0.0, 1.0)


func is_in_combat() -> bool:
	return _combat_timer > 0.0


## Casts the skill in hotbar slot `index` (0-based).
func try_cast_slot(index: int) -> String:
	if index < 0 or index >= _slots.size() or _slots[index] == "":
		return SkillRules.UNKNOWN
	return try_cast(_slots[index])


## Tries to cast `skill_id`. Returns SkillRules.CAN_CAST ("") when it was cast
## or queued until the player walks into range, otherwise the failure reason
## (also emitted as cast_failed).
func try_cast(skill_id: String) -> String:
	if is_dead or _charging:
		return SkillRules.ON_COOLDOWN
	var skill := get_skill(skill_id)
	var reason := SkillRules.check_cast(
		skill, stats.level, mp, cooldowns.remaining(skill_id), _has_valid_target()
	)
	if reason != SkillRules.CAN_CAST:
		cast_failed.emit(skill_id, reason)
		return reason
	if SkillRules.needs_target(skill):
		var distance := global_position.distance_to(current_target.global_position)
		if not SkillRules.in_range(skill, distance):
			_pending_skill = skill_id
			_engaging = true
			return SkillRules.CAN_CAST
	_execute_skill(skill_id, skill)
	return SkillRules.CAN_CAST


func move_to(world_pos: Vector2) -> void:
	if _charging:
		return
	super.move_to(world_pos)


func take_damage(amount: int, source: Node = null, is_crit: bool = false) -> void:
	if is_dead:
		return
	_combat_timer = OUT_OF_COMBAT_DELAY
	super.take_damage(
		CombatRules.reduce_damage(amount, get_damage_taken_multiplier()), source, is_crit
	)


## Brings the player back at spawn_point with full HP/MP.
func respawn() -> void:
	global_position = spawn_point
	is_dead = false
	stop_moving()
	modulate = Color.WHITE
	cooldowns.reset_all()
	_buffs.clear()
	_combat_timer = 0.0
	hp = stats.max_hp()
	mp = stats.max_mp()
	hp_changed.emit(hp, stats.max_hp())
	mp_changed.emit(mp, stats.max_mp())
	buffs_changed.emit()
	respawned.emit()


# --- Frame update ---------------------------------------------------------------


func _physics_process(delta: float) -> void:
	_swing_time = maxf(_swing_time - delta, 0.0)
	_ring_time = maxf(_ring_time - delta, 0.0)
	queue_redraw()
	if is_dead:
		return
	cooldowns.tick(delta)
	_tick_buffs(delta)
	_tick_regen(delta)
	_auto_attack_timer = maxf(_auto_attack_timer - delta, 0.0)
	if _charging:
		return
	if current_target != null and not _has_valid_target():
		clear_target()
	if _engaging and current_target != null:
		_tick_engagement()
	super._physics_process(delta)
	if absf(velocity.x) > 1.0:
		_facing = signf(velocity.x)


func _unhandled_input(event: InputEvent) -> void:
	for i in HOTBAR_SIZE:
		if event.is_action_pressed("skill_%d" % (i + 1)):
			try_cast_slot(i)
			get_viewport().set_input_as_handled()
			return


func _tick_engagement() -> void:
	var distance := global_position.distance_to(current_target.global_position)
	var needed := AUTO_ATTACK_RANGE
	if _pending_skill != "":
		needed = float(get_skill(_pending_skill).get("range", AUTO_ATTACK_RANGE))
	if distance > needed:
		var target_pos := current_target.global_position
		if not is_moving() or target_pos.distance_to(_last_chase_pos) > REPATH_DISTANCE:
			_last_chase_pos = target_pos
			super.move_to(target_pos)
		return
	if is_moving():
		stop_moving()
	_face(current_target.global_position)
	if _pending_skill != "":
		var skill_id := _pending_skill
		_pending_skill = ""
		try_cast(skill_id)
	elif _auto_attack_timer <= 0.0:
		_auto_attack_timer = AUTO_ATTACK_INTERVAL
		_swing_time = 0.2
		_deal_damage(current_target, AUTO_ATTACK_POWER)


func _tick_buffs(delta: float) -> void:
	if _buffs.is_empty():
		return
	for effect: Variant in _buffs.keys():
		var buff: Dictionary = _buffs[effect]
		buff["remaining"] = float(buff["remaining"]) - delta
		if float(buff["remaining"]) <= 0.0:
			_buffs.erase(effect)
			buffs_changed.emit()


func _tick_regen(delta: float) -> void:
	_combat_timer = maxf(_combat_timer - delta, 0.0)
	if is_in_combat():
		return
	if mp < stats.max_mp():
		_mp_regen_acc += stats.max_mp() * MP_REGEN_RATE * delta
		if _mp_regen_acc >= 1.0:
			var whole := int(_mp_regen_acc)
			_mp_regen_acc -= whole
			restore_mp(whole)
	if hp < stats.max_hp():
		_hp_regen_acc += stats.max_hp() * HP_REGEN_RATE * delta
		if _hp_regen_acc >= 1.0:
			var whole_hp := int(_hp_regen_acc)
			_hp_regen_acc -= whole_hp
			heal(whole_hp, self)


# --- Skills ---------------------------------------------------------------------


func _load_skills() -> void:
	_skills = GameData.get_table("skills")
	_slots = SkillRules.ordered_slots(_skills)
	# Typed String arrays pad with "" (empty slot) when growing.
	_slots.resize(HOTBAR_SIZE)


func _execute_skill(skill_id: String, skill: Dictionary) -> void:
	if not spend_mp(int(skill.get("mp_cost", 0))):
		cast_failed.emit(skill_id, SkillRules.NOT_ENOUGH_MP)
		return
	cooldowns.start(skill_id, float(skill.get("cooldown", 0.0)))
	var power: float = float(skill.get("power", 1.0))
	match str(skill.get("effect", "")):
		"damage":
			_engaging = true
			_swing_time = 0.25
			_face(current_target.global_position)
			_deal_damage(current_target, power)
		"charge":
			_engaging = true
			_start_charge(current_target, power)
		"aoe_damage":
			var radius: float = float(skill.get("aoe_radius", 80.0))
			_show_ring(radius, Color(1.0, 0.85, 0.4))
			_swing_time = 0.3
			for enemy in _hostiles_within(radius):
				_deal_damage(enemy, power)
		"buff_attack", "buff_defense":
			var effect := str(skill.get("effect"))
			_buffs[effect] = {
				"amount": float(skill.get("buff_amount", 0.0)),
				"remaining": float(skill.get("duration", 5.0)),
			}
			var color := Color(1, 0.4, 0.3) if effect == "buff_attack" else Color(0.4, 0.7, 1)
			_show_ring(40.0, color)
			buffs_changed.emit()
	skill_cast.emit(skill_id)
	Events.skill_used.emit(self, skill_id)


func _start_charge(target: Actor, power: float) -> void:
	var dir := global_position.direction_to(target.global_position)
	var distance := global_position.distance_to(target.global_position)
	var destination := global_position + dir * maxf(distance - CHARGE_STOP_DISTANCE, 0.0)
	stop_moving()
	_face(target.global_position)
	_charging = true
	var tween := create_tween()
	tween.tween_property(self, "global_position", destination, CHARGE_TIME)
	tween.tween_callback(_finish_charge.bind(target, power))


func _finish_charge(target: Actor, power: float) -> void:
	_charging = false
	_swing_time = 0.25
	if is_dead or not is_instance_valid(target) or target.is_dead:
		return
	_deal_damage(target, power)


func _deal_damage(target: Actor, power: float) -> void:
	if target == null or target.is_dead:
		return
	_combat_timer = OUT_OF_COMBAT_DELAY
	var result := CombatRules.roll_damage(
		stats, target.stats, power, _rng, get_attack_multiplier()
	)
	target.take_damage(result.amount, self, result.is_crit)


func _hostiles_within(radius: float) -> Array[Actor]:
	var found: Array[Actor] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var actor := node as Actor
		if actor == null or actor.is_dead or not is_hostile_to(actor):
			continue
		if global_position.distance_to(actor.global_position) <= radius:
			found.append(actor)
	return found


func _buff_amount(effect: String) -> float:
	var buff: Dictionary = _buffs.get(effect, {})
	return float(buff.get("amount", 0.0))


func _has_valid_target() -> bool:
	return current_target != null and is_instance_valid(current_target) and not current_target.is_dead


# --- Setup / events ---------------------------------------------------------------


func _apply_session_character() -> void:
	var character: Dictionary = Session.character
	display_name = str(character.get("name", "Warrior"))
	stats.level = maxi(1, int(character.get("level", stats.level)))
	stats.bonuses = CombatRules.merge_bonuses(stats.bonuses, get_base_bonuses())


func _on_ground_clicked(world_pos: Vector2) -> void:
	if is_dead:
		return
	# The world may report clicks that landed on an enemy; treat those as targeting.
	var enemy := _enemy_at(world_pos)
	if enemy:
		set_target(enemy, true)
		return
	_engaging = false
	_pending_skill = ""
	move_to(world_pos)


func _enemy_at(world_pos: Vector2) -> Enemy:
	var best: Enemy = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead or not enemy.contains_point(world_pos):
			continue
		var d := enemy.click_distance(world_pos)
		if d < best_distance:
			best_distance = d
			best = enemy
	return best


func _on_actor_died(actor: Node, _killer: Node) -> void:
	if actor == current_target:
		clear_target()


func _on_died(_killer: Node) -> void:
	clear_target()
	_engaging = false
	_pending_skill = ""
	_charging = false
	modulate = Color(1, 1, 1, 0.35)
	get_tree().create_timer(respawn_delay).timeout.connect(respawn)


func _face(world_pos: Vector2) -> void:
	var dx := world_pos.x - global_position.x
	if absf(dx) > 1.0:
		_facing = signf(dx)


func _show_ring(radius: float, color: Color) -> void:
	_ring_radius = radius
	_ring_color = color
	_ring_time = 0.35


# --- Placeholder art ------------------------------------------------------------


func _draw() -> void:
	# Shadow
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 13.0, Color(0, 0, 0, 0.3))
	if _ring_time > 0.0:
		var ring := _ring_color
		ring.a = _ring_time / 0.35
		draw_arc(Vector2.ZERO, _ring_radius, 0.0, TAU, 48, ring, 3.0)
	if _buffs.has("buff_defense"):
		draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 32, Color(0.4, 0.7, 1, 0.8), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var f := _facing
	# Legs, body, head
	draw_rect(Rect2(-7, -10, 5, 10), Color(0.25, 0.2, 0.15))
	draw_rect(Rect2(2, -10, 5, 10), Color(0.25, 0.2, 0.15))
	var armor := Color(1.0, 0.55, 0.45) if _buffs.has("buff_attack") else Color(0.35, 0.45, 0.7)
	draw_rect(Rect2(-9, -28, 18, 19), armor)
	draw_circle(Vector2(0, -34), 7.0, Color(0.96, 0.82, 0.66))
	draw_rect(Rect2(-8, -42, 16, 5), Color(0.6, 0.6, 0.65))
	# Shield (back hand) and sword (front hand); the sword swings when attacking.
	draw_rect(Rect2(-14 * f - 4, -26, 8, 14), Color(0.55, 0.4, 0.2))
	var swing := _swing_time / 0.3
	var hand := Vector2(11 * f, -18)
	var tip := hand + Vector2(f * (8 + 14 * swing), -20 + 18 * swing)
	draw_line(hand, tip, Color(0.85, 0.85, 0.9), 3.0)
