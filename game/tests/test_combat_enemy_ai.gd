extends TestCase

const AI := preload("res://combat/enemies/enemy_ai.gd")

const HOME := Vector2(0, 0)
const AGGRO := 150.0
const LEASH := 400.0
const REACH := 40.0


func _decide(
	state: AI.State, self_pos: Vector2, player_pos: Vector2, has_player: bool = true
) -> AI.State:
	return AI.decide(state, self_pos, HOME, player_pos, has_player, AGGRO, LEASH, REACH)


func test_idle_when_player_far() -> void:
	assert_eq(_decide(AI.State.IDLE, HOME, Vector2(300, 0)), AI.State.IDLE, "far player")


func test_idle_without_player() -> void:
	assert_eq(_decide(AI.State.IDLE, HOME, Vector2.ZERO, false), AI.State.IDLE, "no player")


func test_chase_when_player_in_aggro() -> void:
	assert_eq(_decide(AI.State.IDLE, HOME, Vector2(100, 0)), AI.State.CHASE, "aggro")


func test_attack_when_in_range() -> void:
	assert_eq(_decide(AI.State.CHASE, HOME, Vector2(30, 0)), AI.State.ATTACK, "in reach")
	assert_eq(_decide(AI.State.IDLE, HOME, Vector2(30, 0)), AI.State.ATTACK, "idle to attack")


func test_attack_has_slack() -> void:
	# Slightly out of reach while attacking: keep attacking (no flicker).
	assert_eq(_decide(AI.State.ATTACK, HOME, Vector2(REACH + 4.0, 0)), AI.State.ATTACK, "slack")
	assert_eq(_decide(AI.State.ATTACK, HOME, Vector2(REACH + 30.0, 0)), AI.State.CHASE, "too far")


func test_keeps_chasing_beyond_aggro_radius() -> void:
	var self_pos := Vector2(200, 0)
	assert_eq(_decide(AI.State.CHASE, self_pos, Vector2(380, 0)), AI.State.CHASE, "keep chasing")


func test_leash_when_dragged_too_far() -> void:
	var self_pos := Vector2(LEASH + 10.0, 0)
	assert_eq(_decide(AI.State.CHASE, self_pos, self_pos + Vector2(20, 0)), AI.State.LEASH, "leash")


func test_leash_when_player_dies() -> void:
	assert_eq(_decide(AI.State.ATTACK, Vector2(50, 0), Vector2(60, 0), false), AI.State.LEASH, "dead")


func test_leash_ignores_player_until_home() -> void:
	var near_player := Vector2(110, 0)
	assert_eq(_decide(AI.State.LEASH, Vector2(100, 0), near_player), AI.State.LEASH, "walking home")
	assert_eq(_decide(AI.State.LEASH, Vector2(5, 0), near_player), AI.State.IDLE, "home again")


func test_build_stats_from_data() -> void:
	var data := {
		"level": 3,
		"stats": {"str": 9, "agi": 12, "int": 2, "vit": 6},
		"bonuses": {"max_hp": -100},
		"move_speed": 30.0,
	}
	var s := AI.build_stats(data)
	assert_eq(s.level, 3, "level")
	assert_eq(s.strength, 9, "str")
	assert_eq(s.agility, 12, "agi")
	assert_eq(s.max_hp(), 100 + 6 * 12 + 2 * 20 - 100, "max_hp with bonus")
	assert_near(s.move_speed(), 170.0)
