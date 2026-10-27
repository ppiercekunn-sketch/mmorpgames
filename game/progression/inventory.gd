class_name Inventory
extends RefCounted
## Bag (fixed number of slots, stackable items), equipment map and gold wallet.
## Pure logic: the item table (data/items.json) is passed in as a Dictionary, so
## tests and the M2 server can use it without autoloads. Every mutation emits
## `changed` (and `equipment_changed` for gear); Progression relays these to Events.
##
## A bag slot is either {} (empty) or {"id": String, "qty": int}.
## Equipment maps slot name -> item id ("" = empty).

signal changed()
signal equipment_changed(slot: String)

const DEFAULT_SIZE := 30
const EQUIP_SLOTS := ["weapon", "head", "body", "feet", "ring"]

var item_db: Dictionary = {}
var slots: Array[Dictionary] = []
var equipment: Dictionary = {}
var gold: int = 0


func _init(items: Dictionary = {}, slot_count: int = DEFAULT_SIZE) -> void:
	item_db = items
	for i in slot_count:
		slots.append({})
	for slot in EQUIP_SLOTS:
		equipment[slot] = ""


func get_item_def(item_id: String) -> Dictionary:
	return item_db.get(item_id, {})


func max_stack(item_id: String) -> int:
	return maxi(1, int(get_item_def(item_id).get("max_stack", 1)))


## A copy of the slot contents ({} when empty or out of range).
func get_slot(index: int) -> Dictionary:
	if index < 0 or index >= slots.size():
		return {}
	return slots[index].duplicate()


func is_slot_empty(index: int) -> bool:
	return get_slot(index).is_empty()


## Total quantity of an item across all bag slots.
func count(item_id: String) -> int:
	var total := 0
	for stack in slots:
		if stack.get("id", "") == item_id:
			total += int(stack["qty"])
	return total


## How many of `item_id` could still be added (free stack room + empty slots).
func space_for(item_id: String) -> int:
	var room := 0
	var stack_size := max_stack(item_id)
	for stack in slots:
		if stack.is_empty():
			room += stack_size
		elif stack["id"] == item_id:
			room += stack_size - int(stack["qty"])
	return room


## Adds items, topping up existing stacks first, then filling empty slots.
## Returns the quantity that did NOT fit (0 = everything was added).
func add_item(item_id: String, qty: int) -> int:
	if qty <= 0:
		return 0
	if get_item_def(item_id).is_empty():
		push_warning("Inventory: unknown item '%s'" % item_id)
		return qty
	var left := qty
	var stack_size := max_stack(item_id)
	for stack in slots:
		if left == 0:
			break
		if not stack.is_empty() and stack["id"] == item_id and stack["qty"] < stack_size:
			var moved := mini(left, stack_size - int(stack["qty"]))
			stack["qty"] += moved
			left -= moved
	for i in slots.size():
		if left == 0:
			break
		if slots[i].is_empty():
			var moved := mini(left, stack_size)
			slots[i] = {"id": item_id, "qty": moved}
			left -= moved
	if left != qty:
		changed.emit()
	return left


## Removes `qty` of an item from anywhere in the bag (last stacks first).
## All or nothing: returns false and changes nothing if there are not enough.
func remove_item(item_id: String, qty: int) -> bool:
	if qty <= 0 or count(item_id) < qty:
		return false
	var left := qty
	for i in range(slots.size() - 1, -1, -1):
		if left == 0:
			break
		if slots[i].get("id", "") != item_id:
			continue
		var taken := mini(left, int(slots[i]["qty"]))
		_take_from(i, taken)
		left -= taken
	changed.emit()
	return true


## Removes up to `qty` from one slot; returns how many were removed.
func remove_at(index: int, qty: int = 1) -> int:
	if is_slot_empty(index) or qty <= 0:
		return 0
	var taken := mini(qty, int(slots[index]["qty"]))
	_take_from(index, taken)
	changed.emit()
	return taken


## Moves a slot onto another: merges equal stacks (up to max stack), else swaps.
func move(from_index: int, to_index: int) -> bool:
	if from_index == to_index or is_slot_empty(from_index):
		return false
	if to_index < 0 or to_index >= slots.size():
		return false
	var src: Dictionary = slots[from_index]
	var dst: Dictionary = slots[to_index]
	if not dst.is_empty() and dst["id"] == src["id"]:
		var room := max_stack(src["id"]) - int(dst["qty"])
		if room <= 0:
			return false
		var moved := mini(room, int(src["qty"]))
		dst["qty"] += moved
		_take_from(from_index, moved)
	else:
		slots[from_index] = dst
		slots[to_index] = src
	changed.emit()
	return true


## True if the item is gear and the character meets its level requirement.
## Pass character_level < 0 to skip the level check.
func can_equip(item_id: String, character_level: int = -1) -> bool:
	var def := get_item_def(item_id)
	if def.get("type", "") != "equipment" or not EQUIP_SLOTS.has(def.get("slot", "")):
		return false
	return character_level < 0 or character_level >= int(def.get("level_req", 1))


## Equips the item in bag slot `index`; whatever was equipped takes its bag slot.
func equip_from(index: int, character_level: int = -1) -> bool:
	var stack := get_slot(index)
	if stack.is_empty() or not can_equip(stack["id"], character_level):
		return false
	var slot: String = get_item_def(stack["id"])["slot"]
	var previous: String = equipment[slot]
	equipment[slot] = stack["id"]
	if previous == "":
		_take_from(index, 1)
	elif int(stack["qty"]) == 1:
		slots[index] = {"id": previous, "qty": 1}
	else:
		# Gear normally has max_stack 1; this branch keeps odd data safe.
		if add_item(previous, 1) > 0:
			equipment[slot] = previous
			return false
		_take_from(index, 1)
	changed.emit()
	equipment_changed.emit(slot)
	return true


## Moves the equipped item back into the first free bag slot.
## Fails (returns false) when the slot is empty or the bag is full.
func unequip(slot: String) -> bool:
	var item_id: String = equipment.get(slot, "")
	if item_id == "" or space_for(item_id) <= 0:
		return false
	add_item(item_id, 1)
	equipment[slot] = ""
	equipment_changed.emit(slot)
	return true


## Puts an item straight into its equipment slot without touching the bag
## (starting gear, loading a save). Returns the item id it replaced ("" if none).
func equip_direct(item_id: String) -> String:
	if not can_equip(item_id):
		return ""
	var slot: String = get_item_def(item_id)["slot"]
	var previous: String = equipment[slot]
	equipment[slot] = item_id
	equipment_changed.emit(slot)
	return previous


func get_equipped(slot: String) -> String:
	return equipment.get(slot, "")


## Bag + equipment as plain data for save games (gold is saved separately):
## {"slots": [{} | {"id", "qty"}, ...], "equipment": {slot: item_id}}.
func get_state() -> Dictionary:
	var bag: Array = []
	for stack in slots:
		bag.append(stack.duplicate())
	return {"slots": bag, "equipment": equipment.duplicate()}


## Replaces bag and equipment with a saved state (see get_state()). Trusts
## nothing: unknown items are dropped, stacks are capped at max_stack (the
## overflow is added back where it fits), gear in the wrong slot goes to the
## bag. Slot positions are kept. Emits `changed` and `equipment_changed`.
func set_state(state: Dictionary) -> void:
	var overflow: Array[Dictionary] = []
	for i in slots.size():
		slots[i] = {}
	var saved_slots: Variant = state.get("slots", [])
	if saved_slots is Array:
		for i in (saved_slots as Array).size():
			var stack := _valid_stack(saved_slots[i])
			if stack.is_empty():
				continue
			var keep := mini(int(stack["qty"]), max_stack(stack["id"]))
			if i < slots.size():
				slots[i] = {"id": stack["id"], "qty": keep}
			else:
				keep = 0
			if int(stack["qty"]) > keep:
				overflow.append({"id": stack["id"], "qty": int(stack["qty"]) - keep})
	var saved_gear: Variant = state.get("equipment", {})
	for slot in EQUIP_SLOTS:
		equipment[slot] = ""
		var item_id: Variant = saved_gear.get(slot, "") if saved_gear is Dictionary else ""
		if not item_id is String or item_id == "" or get_item_def(item_id).is_empty():
			continue
		if can_equip(item_id) and get_item_def(item_id)["slot"] == slot:
			equipment[slot] = item_id
		else:
			overflow.append({"id": item_id, "qty": 1})
	for stack in overflow:
		add_item(stack["id"], int(stack["qty"]))
	changed.emit()
	for slot in EQUIP_SLOTS:
		equipment_changed.emit(slot)


## Sum of the "bonuses" of every equipped item.
func gear_bonuses() -> Dictionary:
	var total := {}
	for slot in EQUIP_SLOTS:
		var item_id: String = equipment[slot]
		if item_id != "":
			total = merge_bonuses(total, get_item_def(item_id).get("bonuses", {}))
	return total


func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	changed.emit()


func spend_gold(amount: int) -> bool:
	if amount < 0 or amount > gold:
		return false
	gold -= amount
	changed.emit()
	return true


## Returns a new Dictionary with the values of `a` and `b` added per key.
static func merge_bonuses(a: Dictionary, b: Dictionary) -> Dictionary:
	var merged := a.duplicate()
	for key in b:
		var value: Variant = b[key]
		if merged.has(key):
			# Keep ints as ints so tests and displays stay exact.
			if typeof(merged[key]) == TYPE_INT and typeof(value) == TYPE_INT:
				merged[key] = int(merged[key]) + int(value)
			else:
				merged[key] = float(merged[key]) + float(value)
		else:
			merged[key] = value
	return merged


## {"id", "qty"} for a saved stack of a known item, else {}.
func _valid_stack(entry: Variant) -> Dictionary:
	if not entry is Dictionary:
		return {}
	var item_id: Variant = (entry as Dictionary).get("id")
	var qty: Variant = (entry as Dictionary).get("qty")
	if not item_id is String or get_item_def(item_id).is_empty():
		return {}
	if typeof(qty) != TYPE_INT and typeof(qty) != TYPE_FLOAT:
		return {}
	if int(qty) < 1:
		return {}
	return {"id": item_id, "qty": int(qty)}


func _take_from(index: int, qty: int) -> void:
	var stack: Dictionary = slots[index]
	stack["qty"] = int(stack["qty"]) - qty
	if stack["qty"] <= 0:
		slots[index] = {}
