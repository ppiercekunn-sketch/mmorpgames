class_name PetRules
extends RefCounted
## Pure pet math: stats per level from data/pets.json and a self-contained
## damage formula (so the pet does not hard-depend on combat/ code).

const CRIT_MULTIPLIER := 1.5
const VARIANCE := 0.1


## Builds the pet's Stats for `level` from its pets.json entry:
## base attributes + growth * (level - 1), plus flat "bonuses".
static func build_stats(def: Dictionary, level: int) -> Stats:
	var stats := Stats.new()
	var base: Dictionary = def.get("base", {})
	var growth: Dictionary = def.get("growth", {})
	var steps := maxi(level, 1) - 1
	stats.level = maxi(level, 1)
	stats.strength = int(base.get("strength", 10)) + int(growth.get("strength", 0)) * steps
	stats.agility = int(base.get("agility", 10)) + int(growth.get("agility", 0)) * steps
	stats.intellect = int(base.get("intellect", 10)) + int(growth.get("intellect", 0)) * steps
	stats.vitality = int(base.get("vitality", 10)) + int(growth.get("vitality", 0)) * steps
	stats.bonuses = def.get("bonuses", {}).duplicate()
	return stats


## attack * 100 / (100 + defense), +-10% variance, x1.5 on crit, minimum 1.
## Returns {"amount": int, "crit": bool}.
static func damage(
	attack: int, defense: int, crit_chance: float, rng: RandomNumberGenerator
) -> Dictionary:
	var mitigated := float(attack) * (100.0 / (100.0 + float(maxi(defense, 0))))
	var amount := mitigated * rng.randf_range(1.0 - VARIANCE, 1.0 + VARIANCE)
	var crit := rng.randf() < crit_chance
	if crit:
		amount *= CRIT_MULTIPLIER
	return {"amount": maxi(1, roundi(amount)), "crit": crit}


## The pet's cut of the XP its owner earned (at least 1 when owner earned any).
static func xp_share(owner_xp: int, share: float) -> int:
	if owner_xp <= 0 or share <= 0.0:
		return 0
	return maxi(1, roundi(owner_xp * share))
