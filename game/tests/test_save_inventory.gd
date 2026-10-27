extends TestCase
## Bag + equipment survive a save round trip (Inventory.get_state/set_state
## through SaveGame JSON), and bad saved items are handled safely.

const ITEMS := {
	"potion": {"name": "Potion", "type": "consumable", "max_stack": 5},
	"ore": {"name": "Ore", "type": "material", "max_stack": 99},
	"sword": {"name": "Sword", "type": "equipment", "slot": "weapon",
		"bonuses": {"attack": 6}, "level_req": 1, "max_stack": 1},
	"axe": {"name": "Axe", "type": "equipment", "slot": "weapon",
		"bonuses": {"attack": 10}, "level_req": 5, "max_stack": 1},
	"cap": {"name": "Cap", "type": "equipment", "slot": "head",
		"bonuses": {"defense": 2, "max_hp": 15}, "max_stack": 1},
}


func _round_trip(inv: Inventory) -> Inventory:
	var data := SaveGame.new_save("Tester", "aries")
	data["inventory"] = inv.get_state()
	var loaded := SaveGame.from_json(SaveGame.to_json(data))
	var restored := Inventory.new(ITEMS, inv.slots.size())
	restored.set_state(loaded["inventory"])
	return restored


func test_bag_and_equipment_are_restored() -> void:
	var inv := Inventory.new(ITEMS, 6)
	inv.add_item("potion", 7)
	inv.add_item("ore", 12)
	inv.add_item("axe", 1)
	inv.equip_direct("sword")
	inv.equip_direct("cap")
	inv.move(2, 5)  # leave a gap so slot positions matter
	var restored := _round_trip(inv)
	for i in inv.slots.size():
		assert_eq(restored.get_slot(i), inv.get_slot(i), "slot %d" % i)
	assert_eq(restored.equipment, inv.equipment, "equipment")
	assert_eq(restored.gear_bonuses(), {"attack": 6, "defense": 2, "max_hp": 15}, "gear bonuses")


func test_set_state_emits_change_signals() -> void:
	var inv := Inventory.new(ITEMS, 4)
	var counter := {"changed": 0, "gear": 0}
	inv.changed.connect(func() -> void: counter["changed"] += 1)
	inv.equipment_changed.connect(func(_slot: String) -> void: counter["gear"] += 1)
	inv.set_state({"slots": [{"id": "potion", "qty": 2}], "equipment": {"weapon": "sword"}})
	assert_true(counter["changed"] >= 1, "changed emitted")
	assert_eq(counter["gear"], Inventory.EQUIP_SLOTS.size(), "equipment_changed per slot")


func test_unknown_and_invalid_items_are_dropped() -> void:
	var inv := Inventory.new(ITEMS, 4)
	inv.add_item("ore", 3)
	inv.equip_direct("sword")
	inv.set_state({
		"slots": [{"id": "ghost_item", "qty": 1}, "junk", {"id": "potion", "qty": -2},
			{"id": "potion", "qty": 2}],
		"equipment": {"weapon": "ghost_blade", "head": "cap", "ring": 5},
	})
	assert_eq(inv.get_slot(0), {}, "unknown item dropped")
	assert_eq(inv.get_slot(1), {}, "junk dropped")
	assert_eq(inv.get_slot(2), {}, "negative qty dropped")
	assert_eq(inv.get_slot(3), {"id": "potion", "qty": 2}, "valid stack kept")
	assert_eq(inv.count("ore"), 0, "old bag replaced")
	assert_eq(inv.get_equipped("weapon"), "", "unknown gear dropped")
	assert_eq(inv.get_equipped("head"), "cap", "valid gear kept")
	assert_eq(inv.get_equipped("ring"), "", "bad gear value ignored")


func test_overstacked_and_misplaced_items_go_back_to_the_bag() -> void:
	var inv := Inventory.new(ITEMS, 4)
	inv.set_state({
		"slots": [{"id": "potion", "qty": 8}],
		"equipment": {"head": "sword", "body": "potion"},
	})
	assert_eq(inv.get_slot(0), {"id": "potion", "qty": 5}, "stack capped")
	assert_eq(inv.count("potion"), 9, "overflow + misplaced potion kept in the bag")
	assert_eq(inv.count("sword"), 1, "gear in the wrong slot moved to the bag")
	assert_eq(inv.get_equipped("head"), "", "head empty")
	assert_eq(inv.get_equipped("body"), "", "body empty")


func test_more_saved_slots_than_bag_size() -> void:
	var inv := Inventory.new(ITEMS, 2)
	inv.set_state({"slots": [{}, {}, {"id": "ore", "qty": 4}]})
	assert_eq(inv.count("ore"), 4, "items beyond the bag are added where they fit")
	assert_eq(inv.slots.size(), 2, "bag size unchanged")


func test_state_is_a_copy() -> void:
	var inv := Inventory.new(ITEMS, 2)
	inv.add_item("potion", 1)
	var state := inv.get_state()
	state["slots"][0]["qty"] = 99
	state["equipment"]["weapon"] = "axe"
	assert_eq(inv.get_slot(0)["qty"], 1, "bag untouched")
	assert_eq(inv.get_equipped("weapon"), "", "equipment untouched")
