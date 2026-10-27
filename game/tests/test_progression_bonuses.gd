extends TestCase
## Gear bonus aggregation, merging with the birth-sign base, and pet math.

const ITEMS := {
	"sword": {"type": "equipment", "slot": "weapon", "bonuses": {"attack": 6}},
	"cap": {"type": "equipment", "slot": "head", "bonuses": {"defense": 2, "max_hp": 15}},
	"ring": {"type": "equipment", "slot": "ring",
		"bonuses": {"attack": 2, "crit_chance": 0.02}},
}


func test_gear_bonuses_sum_all_slots() -> void:
	var inv := Inventory.new(ITEMS)
	inv.equip_direct("sword")
	inv.equip_direct("cap")
	inv.equip_direct("ring")
	var total := inv.gear_bonuses()
	assert_eq(total["attack"], 8, "attack")
	assert_eq(total["defense"], 2, "defense")
	assert_eq(total["max_hp"], 15, "max_hp")
	assert_near(float(total["crit_chance"]), 0.02)


func test_empty_equipment_has_no_bonuses() -> void:
	assert_eq(Inventory.new(ITEMS).gear_bonuses(), {}, "no gear")


func test_merge_with_base_bonuses() -> void:
	var base := {"attack": 3, "max_mp": 25}
	var merged := Inventory.merge_bonuses(base, {"attack": 6, "defense": 2})
	assert_eq(merged, {"attack": 9, "max_mp": 25, "defense": 2}, "merged")
	assert_eq(base, {"attack": 3, "max_mp": 25}, "inputs untouched")


func test_merged_bonuses_feed_stats() -> void:
	var inv := Inventory.new(ITEMS)
	inv.equip_direct("sword")
	inv.equip_direct("cap")
	var stats := Stats.new()
	stats.bonuses = Inventory.merge_bonuses({"attack": 3}, inv.gear_bonuses())
	assert_eq(stats.attack(), 23 + 9, "attack with sign + sword")
	assert_eq(stats.max_hp(), 220 + 15, "max_hp with cap")


func test_unequip_removes_bonus() -> void:
	var inv := Inventory.new(ITEMS)
	inv.equip_direct("sword")
	inv.unequip("weapon")
	assert_eq(inv.gear_bonuses(), {}, "bonus gone after unequip")


func test_pet_stats_grow_per_level() -> void:
	var def := {
		"base": {"strength": 6, "agility": 12, "intellect": 4, "vitality": 6},
		"growth": {"strength": 2, "agility": 2, "intellect": 1, "vitality": 2},
		"bonuses": {"move_speed": 40},
	}
	var one := PetRules.build_stats(def, 1)
	var three := PetRules.build_stats(def, 3)
	assert_eq(one.strength, 6, "level 1 strength")
	assert_eq(three.strength, 10, "level 3 strength")
	assert_eq(three.vitality, 10, "level 3 vitality")
	assert_eq(three.level, 3, "level")
	assert_near(one.move_speed(), 180.0, 0.001, "speed bonus")


func test_pet_damage_formula() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 100:
		var hit := PetRules.damage(100, 100, 0.0, rng)
		# 100 * 100/200 = 50, +-10%
		assert_true(hit["amount"] >= 45 and hit["amount"] <= 55, "damage %d" % hit["amount"])
		assert_true(not hit["crit"], "no crits at 0 chance")
	var crit := PetRules.damage(100, 0, 1.0, rng)
	assert_true(crit["crit"] and crit["amount"] >= 135, "crit multiplies")
	assert_eq(PetRules.damage(0, 500, 0.0, rng)["amount"], 1, "minimum 1")


func test_pet_xp_share() -> void:
	assert_eq(PetRules.xp_share(30, 0.5), 15)
	assert_eq(PetRules.xp_share(1, 0.5), 1, "at least 1")
	assert_eq(PetRules.xp_share(0, 0.5), 0, "nothing from nothing")
