class_name EnemyAI
extends RefCounted
## Pure enemy logic: the state-machine decision function and building Stats
## from a data/enemies.json entry. No scene or autoload deps (testable, and
## reusable by the M2 server).
##
## States:
##   IDLE   wander near home
##   CHASE  player is within aggro_radius (or the enemy was hit): run at them
##   ATTACK player within attack_range: stand and hit on attack_cooldown
##   LEASH  dragged further than leash_radius from home: walk home, ignore
##          the player, heal to full on arrival

enum State { IDLE, CHASE, ATTACK, LEASH }

## Distance from home at which a leashing enemy counts as "back home".
const HOME_EPSILON := 10.0
## Extra reach while already attacking, so tiny movements don't flip
## ATTACK <-> CHASE every frame.
const ATTACK_RANGE_SLACK := 8.0


## Returns the next state. `has_player` is false when there is no living
## player to fight. All positions are global.
static func decide(
	state: State,
	self_pos: Vector2,
	home_pos: Vector2,
	player_pos: Vector2,
	has_player: bool,
	aggro_radius: float,
	leash_radius: float,
	attack_range: float
) -> State:
	var from_home := self_pos.distance_to(home_pos)
	if state == State.LEASH:
		return State.IDLE if from_home <= HOME_EPSILON else State.LEASH
	var engaged := state == State.CHASE or state == State.ATTACK
	if from_home > leash_radius or (engaged and not has_player):
		return State.LEASH
	if not has_player:
		return State.IDLE
	var to_player := self_pos.distance_to(player_pos)
	if not engaged and to_player > aggro_radius:
		return State.IDLE
	var reach := attack_range + (ATTACK_RANGE_SLACK if state == State.ATTACK else 0.0)
	return State.ATTACK if to_player <= reach else State.CHASE


## Builds a Stats resource from an enemies.json entry
## (level, stats {str, agi, int, vit}, optional bonuses, move_speed bonus).
static func build_stats(data: Dictionary) -> Stats:
	var s := Stats.new()
	s.level = int(data.get("level", 1))
	var base: Dictionary = data.get("stats", {})
	s.strength = int(base.get("str", 10))
	s.agility = int(base.get("agi", 10))
	s.intellect = int(base.get("int", 10))
	s.vitality = int(base.get("vit", 10))
	var bonuses: Dictionary = data.get("bonuses", {})
	s.bonuses = bonuses.duplicate()
	var speed_bonus: float = float(data.get("move_speed", 0.0))
	if speed_bonus != 0.0:
		s.bonuses["move_speed"] = float(s.bonuses.get("move_speed", 0.0)) + speed_bonus
	return s
