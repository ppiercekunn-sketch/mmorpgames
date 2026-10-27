class_name Leveling
extends RefCounted
## XP and level track for one character (the player or a pet).
## Driven by the data/xp_curve.json table, passed in as a Dictionary:
##   { "max_level": 10, "xp_to_next": [100, 180, ...],
##     "level_gains": {"strength": 2, ...}, "low_level_penalty": {...} }
## Pure logic: no scene or autoload dependencies (tests and the M2 server use it).

const DEFAULT_MAX_LEVEL := 10
const DEFAULT_GAINS := {"strength": 2, "vitality": 2, "agility": 1, "intellect": 1}

var curve: Dictionary = {}
var level: int = 1
## XP earned inside the current level (resets to 0 on each level up).
var xp: int = 0


func _init(curve_data: Dictionary = {}, start_level: int = 1, start_xp: int = 0) -> void:
	curve = curve_data
	level = clampi(start_level, 1, max_level())
	xp = 0
	if not is_max_level():
		xp = clampi(start_xp, 0, xp_to_next() - 1)


func max_level() -> int:
	return int(curve.get("max_level", DEFAULT_MAX_LEVEL))


func is_max_level() -> bool:
	return level >= max_level()


## XP needed to go from the current level to the next (0 at the cap).
func xp_to_next() -> int:
	return xp_required(curve, level)


## 0.0 - 1.0 progress through the current level (1.0 at the cap).
func progress() -> float:
	if is_max_level():
		return 1.0
	return float(xp) / float(xp_to_next())


## Adds XP and returns how many levels were gained (0 if none).
## XP stops accumulating at the level cap.
func add_xp(amount: int) -> int:
	if amount <= 0 or is_max_level():
		return 0
	xp += amount
	var gained := 0
	while not is_max_level() and xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		gained += 1
	if is_max_level():
		xp = 0
	return gained


## XP needed to advance from `for_level` to the next one, per the curve.
static func xp_required(curve_data: Dictionary, for_level: int) -> int:
	var table: Array = curve_data.get("xp_to_next", [])
	var cap := int(curve_data.get("max_level", DEFAULT_MAX_LEVEL))
	if for_level < 1 or for_level >= cap or for_level - 1 >= table.size():
		return 0
	return maxi(1, int(table[for_level - 1]))


## XP for a kill, reduced when the enemy is far below the killer's level.
## With the default curve: 5 levels below = 50%, then -10% per extra level, min 10%.
static func scaled_xp(
	base_xp: int, killer_level: int, enemy_level: int, curve_data: Dictionary
) -> int:
	if base_xp <= 0:
		return 0
	var penalty: Dictionary = curve_data.get("low_level_penalty", {})
	var start_gap := int(penalty.get("level_gap", 5))
	var gap := killer_level - enemy_level
	if gap < start_gap:
		return base_xp
	var mult := float(penalty.get("multiplier", 0.5))
	mult -= float(penalty.get("step", 0.1)) * float(gap - start_gap)
	mult = maxf(mult, float(penalty.get("minimum", 0.1)))
	return maxi(1, roundi(base_xp * mult))


## Raises `stats.level` by `levels` and adds the per-level attribute gains.
static func apply_level_gains(stats: Stats, levels: int, curve_data: Dictionary) -> void:
	if levels <= 0:
		return
	var gains: Dictionary = curve_data.get("level_gains", DEFAULT_GAINS)
	stats.level += levels
	stats.strength += int(gains.get("strength", 0)) * levels
	stats.agility += int(gains.get("agility", 0)) * levels
	stats.intellect += int(gains.get("intellect", 0)) * levels
	stats.vitality += int(gains.get("vitality", 0)) * levels
