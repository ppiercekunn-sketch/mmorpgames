extends TestCase

const Rules := preload("res://combat/combat_rules.gd")


func _rng(seed_value: int = 1234) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_minimum_damage_is_one() -> void:
	var weakling := Stats.new()
	weakling.strength = 0
	weakling.bonuses = {"attack": -3}
	var tank := Stats.new()
	tank.vitality = 500
	var rng := _rng()
	for i in 50:
		var result := Rules.roll_damage(weakling, tank, 0.1, rng)
		assert_eq(result.amount, 1, "min damage")
	assert_eq(Rules.compute_damage(0.0, 1.0, 0, 0.0, false), 1, "zero attack")


func test_crit_multiplier() -> void:
	assert_eq(Rules.compute_damage(100.0, 1.0, 0, 0.0, false), 100, "normal")
	assert_eq(Rules.compute_damage(100.0, 1.0, 0, 0.0, true), 150, "crit")


func test_crit_chance_extremes() -> void:
	var rng := _rng(7)
	for i in 100:
		assert_true(Rules.roll_damage_values(100.0, 1.0, 0, 1.0, rng).is_crit, "always crit")
		assert_true(not Rules.roll_damage_values(100.0, 0.0, 0, 1.0, rng).is_crit, "never crit")


func test_defense_reduces_damage() -> void:
	assert_eq(Rules.compute_damage(100.0, 1.0, 0, 0.0, false), 100, "no defense")
	assert_eq(Rules.compute_damage(100.0, 1.0, 100, 0.0, false), 50, "100 defense halves")
	assert_eq(Rules.compute_damage(100.0, 1.0, 300, 0.0, false), 25, "300 defense quarters")

	var attacker := Stats.new()
	var soft := Stats.new()
	soft.vitality = 0
	soft.agility = 0
	var hard := Stats.new()
	hard.vitality = 80
	var rng_a := _rng(99)
	var rng_b := _rng(99)
	var total_soft := 0
	var total_hard := 0
	for i in 200:
		total_soft += Rules.roll_damage(attacker, soft, 1.0, rng_a).amount
		total_hard += Rules.roll_damage(attacker, hard, 1.0, rng_b).amount
	assert_true(total_hard < total_soft, "higher defense deals less in total")


func test_power_scales_damage() -> void:
	assert_eq(Rules.compute_damage(50.0, 2.0, 0, 0.0, false), 100, "power 2")


func test_variance_stays_within_ten_percent() -> void:
	var rng := _rng(42)
	for i in 300:
		var result := Rules.roll_damage_values(100.0, 0.0, 0, 1.0, rng)
		assert_true(result.amount >= 90 and result.amount <= 110, "variance %d" % result.amount)


func test_same_seed_same_result() -> void:
	var a := Stats.new()
	var d := Stats.new()
	var first := Rules.roll_damage(a, d, 1.5, _rng(5))
	var second := Rules.roll_damage(a, d, 1.5, _rng(5))
	assert_eq(first.amount, second.amount, "deterministic amount")
	assert_eq(first.is_crit, second.is_crit, "deterministic crit")


func test_reduce_damage_keeps_minimum() -> void:
	assert_eq(Rules.reduce_damage(100, 0.6), 60, "shield wall")
	assert_eq(Rules.reduce_damage(1, 0.1), 1, "min 1")


func test_merge_bonuses_sums_keys() -> void:
	var merged := Rules.merge_bonuses({"attack": 3, "max_hp": 10}, {"attack": 2, "defense": 1})
	assert_near(float(merged["attack"]), 5.0)
	assert_near(float(merged["max_hp"]), 10.0)
	assert_near(float(merged["defense"]), 1.0)
