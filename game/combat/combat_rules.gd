class_name CombatRules
extends RefCounted
## Damage formula and other pure combat math.
## No scene or autoload dependencies so the headless server (M2) and the tests
## can use it directly. Randomness always comes from a caller-supplied
## RandomNumberGenerator so results are reproducible with a fixed seed.

## Damage multiplier applied on a critical hit.
const CRIT_MULTIPLIER := 1.5
## Damage varies by up to +/- this fraction on every hit.
const VARIANCE := 0.1
## Defense mitigation: damage * DEFENSE_SCALE / (DEFENSE_SCALE + defense).
## 100 defense halves damage, 300 defense quarters it (diminishing returns).
const DEFENSE_SCALE := 100.0


## Outcome of one damage roll.
class DamageResult:
	extends RefCounted
	var amount: int = 0
	var is_crit: bool = false

	func _init(p_amount: int = 0, p_is_crit: bool = false) -> void:
		amount = p_amount
		is_crit = p_is_crit


## Fraction of incoming damage that gets through a given defense (0..1].
static func mitigation(defense: int) -> float:
	return DEFENSE_SCALE / (DEFENSE_SCALE + float(maxi(defense, 0)))


## Deterministic core of the formula. `variance_roll` is in [-VARIANCE, VARIANCE].
## Always returns at least 1.
static func compute_damage(
	attack: float, power: float, defense: int, variance_roll: float, is_crit: bool
) -> int:
	var raw := attack * power * mitigation(defense) * (1.0 + variance_roll)
	if is_crit:
		raw *= CRIT_MULTIPLIER
	return maxi(1, roundi(raw))


## Rolls variance and crit from raw numbers. Use this when the attacker's
## attack has already been modified (e.g. by a buff).
static func roll_damage_values(
	attack: float, crit_chance: float, defense: int, power: float, rng: RandomNumberGenerator
) -> DamageResult:
	var variance_roll := rng.randf_range(-VARIANCE, VARIANCE)
	var is_crit := rng.randf() < crit_chance
	return DamageResult.new(compute_damage(attack, power, defense, variance_roll, is_crit), is_crit)


## Rolls one hit from `attacker` against `defender`.
## `power` is the skill multiplier (1.0 for a basic attack);
## `attack_multiplier` scales the attacker's attack (temporary buffs).
static func roll_damage(
	attacker: Stats,
	defender: Stats,
	power: float,
	rng: RandomNumberGenerator,
	attack_multiplier: float = 1.0
) -> DamageResult:
	return roll_damage_values(
		attacker.attack() * attack_multiplier,
		attacker.crit_chance(),
		defender.defense(),
		power,
		rng
	)


## Applies a damage-taken multiplier (e.g. a shield buff) to an incoming hit,
## keeping the minimum of 1.
static func reduce_damage(amount: int, damage_taken_multiplier: float) -> int:
	return maxi(1, roundi(amount * damage_taken_multiplier))


## Sums two bonus dictionaries key by key (numeric values). Used to merge the
## birth-sign passive into Stats.bonuses.
static func merge_bonuses(a: Dictionary, b: Dictionary) -> Dictionary:
	var result := a.duplicate()
	for key: Variant in b:
		result[key] = float(result.get(key, 0)) + float(b[key])
	return result
