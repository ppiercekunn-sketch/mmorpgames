class_name Stats
extends Resource
## Character stats. Pure data plus derived-stat math, no scene dependencies,
## so the headless server can use the same code.

@export var level: int = 1
@export var strength: int = 10
@export var agility: int = 10
@export var intellect: int = 10
@export var vitality: int = 10

## Flat bonuses from gear, sigils, birth sign. Keys match the derived stat names
## below ("attack", "defense", "max_hp", "max_mp", "crit_chance", "move_speed").
@export var bonuses: Dictionary = {}


func _bonus(key: String) -> float:
	return float(bonuses.get(key, 0))


func max_hp() -> int:
	return int(100 + vitality * 12 + (level - 1) * 20 + _bonus("max_hp"))


func max_mp() -> int:
	return int(50 + intellect * 6 + (level - 1) * 8 + _bonus("max_mp"))


func attack() -> int:
	return int(strength * 2 + level * 3 + _bonus("attack"))


func defense() -> int:
	return int(vitality + agility / 2.0 + level * 2 + _bonus("defense"))


## 0.0 - 1.0
func crit_chance() -> float:
	return clampf(0.05 + agility * 0.002 + _bonus("crit_chance"), 0.0, 0.75)


## Pixels per second.
func move_speed() -> float:
	return 140.0 + _bonus("move_speed")


func duplicate_stats() -> Stats:
	var s := Stats.new()
	s.level = level
	s.strength = strength
	s.agility = agility
	s.intellect = intellect
	s.vitality = vitality
	s.bonuses = bonuses.duplicate(true)
	return s
