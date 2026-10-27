extends TestCase

const ITEMS := {
	"potion": {"name": "Potion", "type": "consumable", "max_stack": 5},
	"ore": {"name": "Ore", "type": "material", "max_stack": 99},
	"sword": {"name": "Sword", "type": "equipment", "slot": "weapon",
		"bonuses": {"attack": 6}, "level_req": 1},
	"axe": {"name": "Axe", "type": "equipment", "slot": "weapon",
		"bonuses": {"attack": 10, "crit_chance": 0.02}, "level_req": 5},
	"cap": {"name": "Cap", "type": "equipment", "slot": "head",
		"bonuses": {"defense": 2, "max_hp": 15}},
}


func _inv(slots: int = 4) -> Inventory:
	return Inventory.new(ITEMS, slots)


func test_stacks_fill_existing_then_new_slots() -> void:
	var inv := _inv()
	assert_eq(inv.add_item("potion", 3), 0, "leftover")
	assert_eq(inv.add_item("potion", 4), 0, "leftover")
	assert_eq(inv.get_slot(0), {"id": "potion", "qty": 5}, "slot 0 full stack")
	assert_eq(inv.get_slot(1), {"id": "potion", "qty": 2}, "slot 1 remainder")
	assert_eq(inv.count("potion"), 7, "count")


func test_full_bag_returns_leftover() -> void:
	var inv := _inv(2)
	assert_eq(inv.add_item("potion", 12), 2, "only 10 fit")
	assert_eq(inv.count("potion"), 10, "count")
	assert_eq(inv.space_for("potion"), 0, "no space")
	assert_eq(inv.add_item("ore", 1), 1, "no room for a new item")


func test_unknown_item_is_rejected() -> void:
	var inv := _inv()
	assert_eq(inv.add_item("nope", 2), 2, "leftover")
	assert_true(inv.is_slot_empty(0), "slot still empty")


func test_remove_item_is_all_or_nothing() -> void:
	var inv := _inv()
	inv.add_item("potion", 7)
	assert_true(not inv.remove_item("potion", 8), "not enough")
	assert_eq(inv.count("potion"), 7, "unchanged")
	assert_true(inv.remove_item("potion", 3), "removed")
	assert_eq(inv.count("potion"), 4, "count after remove")


func test_remove_at_clears_empty_slot() -> void:
	var inv := _inv()
	inv.add_item("ore", 1)
	assert_eq(inv.remove_at(0, 5), 1, "removed only what was there")
	assert_true(inv.is_slot_empty(0), "slot emptied")


func test_move_swaps_and_merges() -> void:
	var inv := _inv()
	inv.add_item("ore", 3)
	assert_true(inv.move(0, 2), "move to empty")
	assert_true(inv.is_slot_empty(0), "source empty")
	assert_eq(inv.get_slot(2), {"id": "ore", "qty": 3})
	inv.add_item("potion", 1)
	assert_true(inv.move(0, 2), "swap")
	assert_eq(inv.get_slot(0)["id"], "ore", "swapped back")
	assert_eq(inv.get_slot(2)["id"], "potion", "swapped in")
	inv.slots[1] = {"id": "potion", "qty": 4}
	assert_true(inv.move(1, 2), "merge")
	assert_eq(inv.get_slot(2)["qty"], 5, "merged to max stack")
	assert_true(inv.is_slot_empty(1), "merged source emptied")


func test_equip_swaps_with_bag_slot() -> void:
	var inv := _inv()
	inv.equip_direct("sword")
	inv.add_item("axe", 1)
	assert_true(inv.equip_from(0), "equip axe")
	assert_eq(inv.get_equipped("weapon"), "axe", "axe equipped")
	assert_eq(inv.get_slot(0), {"id": "sword", "qty": 1}, "sword took the axe's slot")


func test_equip_respects_level_and_type() -> void:
	var inv := _inv()
	inv.add_item("axe", 1)
	inv.add_item("potion", 1)
	assert_true(not inv.equip_from(0, 3), "level 3 cannot equip level 5 axe")
	assert_true(not inv.equip_from(1), "potions are not gear")
	assert_true(inv.equip_from(0, 5), "level 5 can")
	assert_true(inv.is_slot_empty(0), "empty slot after equipping into empty gear slot")


func test_unequip_needs_bag_space() -> void:
	var inv := _inv(1)
	inv.equip_direct("cap")
	inv.add_item("ore", 1)
	assert_true(not inv.unequip("head"), "bag full")
	assert_eq(inv.get_equipped("head"), "cap", "still equipped")
	inv.remove_at(0, 1)
	assert_true(inv.unequip("head"), "unequipped")
	assert_eq(inv.get_equipped("head"), "", "slot empty")
	assert_eq(inv.count("cap"), 1, "cap in bag")


func test_signals_fire_on_changes() -> void:
	var inv := _inv()
	var events: Array[String] = []
	inv.changed.connect(func() -> void: events.append("changed"))
	inv.equipment_changed.connect(func(slot: String) -> void: events.append("equip:" + slot))
	inv.add_item("sword", 1)
	inv.equip_from(0)
	assert_true(events.has("changed"), "changed emitted")
	assert_true(events.has("equip:weapon"), "equipment_changed emitted")


func test_gold_wallet() -> void:
	var inv := _inv()
	inv.add_gold(50)
	assert_true(not inv.spend_gold(60), "cannot overspend")
	assert_true(inv.spend_gold(20), "spend")
	assert_eq(inv.gold, 30, "gold")
