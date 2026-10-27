extends TestCase

const CURVE := {
	"max_level": 4,
	"xp_to_next": [100, 200, 300],
	"level_gains": {"strength": 2, "vitality": 2, "agility": 1, "intellect": 1},
	"low_level_penalty": {"level_gap": 5, "multiplier": 0.5, "step": 0.1, "minimum": 0.1},
}


func test_add_xp_without_level_up() -> void:
	var track := Leveling.new(CURVE)
	assert_eq(track.add_xp(40), 0, "levels gained")
	assert_eq(track.level, 1, "level")
	assert_eq(track.xp, 40, "xp")
	assert_near(track.progress(), 0.4)


func test_add_xp_levels_up_with_carry_over() -> void:
	var track := Leveling.new(CURVE)
	assert_eq(track.add_xp(130), 1, "levels gained")
	assert_eq(track.level, 2, "level")
	assert_eq(track.xp, 30, "carry-over xp")
	assert_eq(track.xp_to_next(), 200, "next requirement")


func test_add_xp_multiple_levels_at_once() -> void:
	var track := Leveling.new(CURVE)
	assert_eq(track.add_xp(350), 2, "levels gained")
	assert_eq(track.level, 3, "level")
	assert_eq(track.xp, 50, "xp")


func test_level_cap() -> void:
	var track := Leveling.new(CURVE)
	assert_eq(track.add_xp(100000), 3, "capped levels gained")
	assert_eq(track.level, 4, "level is max")
	assert_eq(track.xp, 0, "no xp at cap")
	assert_true(track.is_max_level(), "is max level")
	assert_eq(track.add_xp(500), 0, "no levels past cap")
	assert_eq(track.xp_to_next(), 0, "no requirement at cap")


func test_zero_or_negative_xp_is_ignored() -> void:
	var track := Leveling.new(CURVE)
	assert_eq(track.add_xp(0), 0)
	assert_eq(track.add_xp(-50), 0)
	assert_eq(track.xp, 0)


func test_start_level_and_xp_are_clamped() -> void:
	var track := Leveling.new(CURVE, 2, 9999)
	assert_eq(track.level, 2, "level")
	assert_eq(track.xp, 199, "xp clamped below next requirement")
	var capped := Leveling.new(CURVE, 99, 10)
	assert_eq(capped.level, 4, "level clamped to cap")


func test_low_level_enemies_give_reduced_xp() -> void:
	assert_eq(Leveling.scaled_xp(100, 5, 1, CURVE), 100, "gap 4: full xp")
	assert_eq(Leveling.scaled_xp(100, 6, 1, CURVE), 50, "gap 5: half")
	assert_eq(Leveling.scaled_xp(100, 8, 1, CURVE), 30, "gap 7: 30%")
	assert_eq(Leveling.scaled_xp(100, 30, 1, CURVE), 10, "floor at 10%")
	assert_eq(Leveling.scaled_xp(1, 30, 1, CURVE), 1, "never below 1")
	assert_eq(Leveling.scaled_xp(100, 1, 9, CURVE), 100, "higher enemy: full xp")


func test_apply_level_gains() -> void:
	var stats := Stats.new()
	Leveling.apply_level_gains(stats, 2, CURVE)
	assert_eq(stats.level, 3, "level")
	assert_eq(stats.strength, 14, "strength")
	assert_eq(stats.vitality, 14, "vitality")
	assert_eq(stats.agility, 12, "agility")
	assert_eq(stats.intellect, 12, "intellect")


func test_shipped_curve_is_valid() -> void:
	var curve: Dictionary = _load_json("res://data/xp_curve.json")
	assert_eq(int(curve.get("max_level", 0)), 10, "MVP cap")
	var table: Array = curve.get("xp_to_next", [])
	assert_eq(table.size(), 9, "one entry per level below the cap")
	for i in range(1, table.size()):
		assert_true(table[i] > table[i - 1], "curve increases at %d" % i)


func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
