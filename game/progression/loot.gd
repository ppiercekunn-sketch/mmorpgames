class_name Loot
extends RefCounted
## Loot table rolls. Pure logic: tables come from data/loot_tables.json as
## Dictionaries and randomness from an injected RandomNumberGenerator, so rolls
## are deterministic under a fixed seed (tests, M2 server).
##
## Table format:
##   { "gold_min": 1, "gold_max": 4,
##     "entries": [ {"item_id": "hp_potion", "chance": 0.2, "min_qty": 1, "max_qty": 1}, ... ] }
## Every entry is rolled independently.


## Returns { "gold": int, "items": [ {"id": String, "qty": int}, ... ] }.
static func roll(table: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var result := {"gold": 0, "items": []}
	var gold_min := int(table.get("gold_min", 0))
	var gold_max := int(table.get("gold_max", gold_min))
	if gold_max > 0:
		result["gold"] = rng.randi_range(maxi(gold_min, 0), maxi(gold_max, gold_min))
	var items: Array = result["items"]
	for entry in table.get("entries", []):
		var drop := roll_entry(entry, rng)
		if not drop.is_empty():
			items.append(drop)
	return result


## Rolls one entry. Returns {"id", "qty"} or {} when it did not drop.
static func roll_entry(entry: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var item_id := str(entry.get("item_id", ""))
	if item_id == "":
		return {}
	var chance := clampf(float(entry.get("chance", 0.0)), 0.0, 1.0)
	if chance <= 0.0:
		return {}
	# Guaranteed drops (chance 1.0) skip the roll.
	if chance < 1.0 and rng.randf() >= chance:
		return {}
	var min_qty := maxi(1, int(entry.get("min_qty", 1)))
	var max_qty := maxi(min_qty, int(entry.get("max_qty", min_qty)))
	return {"id": item_id, "qty": rng.randi_range(min_qty, max_qty)}
