class_name Actor
extends CharacterBody2D
## Base for anything that moves and fights: players, enemies, pets.
## Movement: call move_to(world_pos); a NavigationAgent2D child named
## "NavAgent" is used for pathfinding if present, otherwise straight-line.
## Combat: take_damage()/heal() update hp and emit Events; never set hp directly.

signal hp_changed(current: int, maximum: int)
signal mp_changed(current: int, maximum: int)
signal died(killer: Node)
signal arrived()

enum Team { PLAYER, ENEMY, NEUTRAL }

@export var display_name: String = "Actor"
@export var team: Team = Team.NEUTRAL
@export var stats: Stats

var hp: int = 0
var mp: int = 0
var is_dead: bool = false
var _move_target: Vector2
var _moving: bool = false

@onready var nav_agent: NavigationAgent2D = get_node_or_null("NavAgent")


func _ready() -> void:
	if stats == null:
		stats = Stats.new()
	hp = stats.max_hp()
	mp = stats.max_mp()


func move_to(world_pos: Vector2) -> void:
	if is_dead:
		return
	_move_target = world_pos
	_moving = true
	if nav_agent:
		nav_agent.target_position = world_pos


func stop_moving() -> void:
	_moving = false
	velocity = Vector2.ZERO


func is_moving() -> bool:
	return _moving


func _physics_process(_delta: float) -> void:
	if not _moving or is_dead:
		return
	var next_point := _move_target
	if nav_agent:
		if nav_agent.is_navigation_finished():
			_finish_move()
			return
		next_point = nav_agent.get_next_path_position()
	elif global_position.distance_to(_move_target) < 4.0:
		_finish_move()
		return
	velocity = global_position.direction_to(next_point) * stats.move_speed()
	move_and_slide()


func _finish_move() -> void:
	stop_moving()
	arrived.emit()


func take_damage(amount: int, source: Node = null, is_crit: bool = false) -> void:
	if is_dead:
		return
	hp = max(hp - amount, 0)
	hp_changed.emit(hp, stats.max_hp())
	Events.actor_damaged.emit(self, amount, source, is_crit)
	if hp == 0:
		die(source)


func heal(amount: int, source: Node = null) -> void:
	if is_dead:
		return
	hp = min(hp + amount, stats.max_hp())
	hp_changed.emit(hp, stats.max_hp())
	Events.actor_healed.emit(self, amount, source)


func spend_mp(amount: int) -> bool:
	if mp < amount:
		return false
	mp -= amount
	mp_changed.emit(mp, stats.max_mp())
	return true


func restore_mp(amount: int) -> void:
	mp = min(mp + amount, stats.max_mp())
	mp_changed.emit(mp, stats.max_mp())


func die(killer: Node = null) -> void:
	if is_dead:
		return
	is_dead = true
	stop_moving()
	died.emit(killer)
	Events.actor_died.emit(self, killer)


func is_hostile_to(other: Actor) -> bool:
	if other == null or other.team == Team.NEUTRAL or team == Team.NEUTRAL:
		return false
	return other.team != team
