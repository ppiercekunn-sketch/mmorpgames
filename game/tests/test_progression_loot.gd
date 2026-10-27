extends TestCase

const TABLE := {
	"gold_min": 5,
	"gold_max": 10,
	"entries": [
		{"item_id": "always", "chance": 1.0, "min_qty": 2, "max_qty": 4},
		{"item_id": "never", "chance": 0.0, "min_qty": 1, "max_qty": 1},
		{"item_id": "sometimes", "chance": 0.3, "min_qty": 1, "max_qty": 1},
	],
}


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_same_seed_same_result() -> void:
	var a := Loot.roll(TABLE, _rng(1234))
	var b := Loot.roll(TABLE, _rng(1234))
	assert_eq(a, b, "deterministic roll")


func test_guaranteed_and_impossible_entries() -> void:
	var rng := _rng(7)
	for i in 200:
		var result := Loot.roll(TABLE, rng)
		var ids: Array = result["items"].map(func(d: Dictionary) -> String: return d["id"])
		assert_true(ids.has("always"), "chance 1.0 always drops")
		assert_true(not ids.has("never"), "chance 0.0 never drops")


func test_quantities_and_gold_in_range() -> void:
	var rng := _rng(99)
	for i in 200:
		var result := Loot.roll(TABLE, rng)
		var gold: int = result["gold"]
		assert_true(gold >= 5 and gold <= 10, "gold %d in range" % gold)
		for drop in result["items"]:
			if drop["id"] == "always":
				assert_true(drop["qty"] >= 2 and drop["qty"] <= 4, "qty in range")


func test_drop_rate_roughly_matches_chance() -> void:
	var rng := _rng(42)
	var hits := 0
	var rolls := 2000
	for i in rolls:
		var drop := Loot.roll_entry(TABLE["entries"][2], rng)
		if not drop.is_empty():
			hits += 1
	var rate := float(hits) / rolls
	assert_true(rate > 0.25 and rate < 0.35, "rate %.3f near 0.3" % rate)


func test_no_gold_when_table_has_none() -> void:
	var result := Loot.roll({"entries": []}, _rng(1))
	assert_eq(result["gold"], 0, "gold")
	assert_eq(result["items"].size(), 0, "items")


func test_shipped_tables_reference_known_items() -> void:
	var items := _load_json("res://data/items.json")
	var tables := _load_json("res://data/loot_tables.json")
	for table_id in ["slime_drops", "wolf_drops", "bandit_drops", "boss_drops"]:
		assert_true(tables.has(table_id), "table %s exists" % table_id)
	for table_id in tables:
		for entry in tables[table_id].get("entries", []):
			assert_true(items.has(entry["item_id"]),
				"%s: unknown item %s" % [table_id, entry["item_id"]])


func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
