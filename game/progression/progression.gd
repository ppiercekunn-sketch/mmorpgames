class_name Progression
extends Node
## Progression layer: XP and levels, loot drops and pickup, inventory and
## equipment, the starter pet and the progression UI.
##
## Usage (game scene): add a Progression node, then call
## `setup(player, zone.get_entities_root())`. It listens to Events.actor_died,
## awards XP for enemies killed by the player or the player's pet, drops loot,
## and rebuilds `player.stats.bonuses` (birth sign + gear) after every gear change.
## The pure logic lives in Leveling, Loot, Inventory and PetRules.

## A short player-facing message ("+3 gold", "Your bag is full."), shown by the UI.
signal notice(text: String)

const GROUP := "progression"
const PET_SCENE := preload("res://progression/pet/pet.tscn")
const UI_SCENE_PATH := "res://progression/ui/progression_ui.tscn"
const LootPickup := preload("res://progression/loot/loot_pickup.gd")
const LevelUpFlash := preload("res://progression/fx/level_up_flash.gd")
const STARTER_WEAPON := "novice_sword"
const STARTER_ITEMS := {"hp_potion": 3}
const STARTER_PET := "star_pup"
const PET_SPAWN_OFFSET := Vector2(-30.0, 14.0)
const DROP_SCATTER := 28.0
const RARITY_COLORS := {
	"common": Color(0.82, 0.82, 0.82),
	"uncommon": Color(0.4, 0.88, 0.4),
	"rare": Color(0.38, 0.62, 1.0),
	"epic": Color(0.78, 0.45, 1.0),
}

## Instance progression_ui.tscn during setup() unless one is already in the tree.
@export var create_ui: bool = true

var player: Actor
var entities_root: Node2D
var inventory: Inventory
var player_leveling: Leveling
var pet: Pet
var xp_curve: Dictionary = {}
var rng := RandomNumberGenerator.new()

var _last_gold: int = 0
var _is_set_up: bool = false


func _enter_tree() -> void:
	add_to_group(GROUP)


## Wires everything for `p_player`. Drops and the pet go under `p_entities_root`.
func setup(p_player: Actor, p_entities_root: Node2D) -> void:
	player = p_player
	entities_root = p_entities_root
	rng.randomize()
	xp_curve = GameData.get_table("xp_curve")
	inventory = Inventory.new(GameData.get_table("items"))
	_load_character_state()
	_give_starting_gear()
	inventory.changed.connect(_on_inventory_changed)
	inventory.equipment_changed.connect(_on_equipment_changed)
	refresh_player_bonuses()
	if not Events.actor_died.is_connected(_on_actor_died):
		Events.actor_died.connect(_on_actor_died)
	_spawn_pet()
	_is_set_up = true
	_bind_ui()
	Events.inventory_changed.emit()
	Events.gold_changed.emit(inventory.gold)
	for slot in Inventory.EQUIP_SLOTS:
		Events.equipment_changed.emit(slot)


func is_set_up() -> bool:
	return _is_set_up


func get_level() -> int:
	return player_leveling.level if player_leveling else 1


## XP inside the current level.
func get_xp() -> int:
	return player_leveling.xp if player_leveling else 0


## XP needed for the next level (0 at the level cap).
func get_xp_to_next() -> int:
	return player_leveling.xp_to_next() if player_leveling else 0


func get_item_def(item_id: String) -> Dictionary:
	return inventory.get_item_def(item_id) if inventory else {}


## Gives the player XP (kills call this; also handy for quests/debug).
## Returns the number of levels gained.
func award_xp(amount: int) -> int:
	if amount <= 0 or player_leveling == null or not is_instance_valid(player):
		return 0
	var gained := player_leveling.add_xp(amount)
	Events.xp_gained.emit(player, amount)
	if gained > 0:
		_on_player_leveled(gained)
	_sync_session()
	return gained


## Rolls `table_id` from loot_tables.json and spawns the drops around `world_pos`.
func drop_loot(table_id: String, world_pos: Vector2) -> void:
	var table := GameData.get_entry("loot_tables", table_id)
	if table.is_empty():
		push_warning("Progression: unknown loot table '%s'" % table_id)
		return
	var result := Loot.roll(table, rng)
	if int(result["gold"]) > 0:
		var gold_drop := LootPickup.new()
		gold_drop.setup_gold(int(result["gold"]))
		_place_pickup(gold_drop, world_pos)
		Events.loot_dropped.emit("gold", int(result["gold"]), world_pos)
	for drop in result["items"]:
		var item_id: String = drop["id"]
		var def := get_item_def(item_id)
		if def.is_empty():
			push_warning("Progression: loot table '%s' has unknown item '%s'" % [table_id, item_id])
			continue
		var pickup := LootPickup.new()
		pickup.setup_item(item_id, int(drop["qty"]), str(def.get("name", item_id)),
			rarity_color(str(def.get("rarity", "common"))))
		_place_pickup(pickup, world_pos)
		Events.loot_dropped.emit(item_id, int(drop["qty"]), world_pos)


## Left-click on a bag slot: equips gear, uses consumables.
func activate_slot(index: int) -> bool:
	var stack := inventory.get_slot(index)
	if stack.is_empty():
		return false
	match str(get_item_def(stack["id"]).get("type", "")):
		"equipment":
			return equip_from_bag(index)
		"consumable":
			return use_item(index)
	return false


func equip_from_bag(index: int) -> bool:
	var stack := inventory.get_slot(index)
	if stack.is_empty():
		return false
	var def := get_item_def(stack["id"])
	if not inventory.can_equip(stack["id"], get_level()):
		if def.get("type", "") == "equipment":
			notice.emit("Requires level %d." % int(def.get("level_req", 1)))
		return false
	return inventory.equip_from(index, get_level())


func unequip(slot: String) -> bool:
	if inventory.get_equipped(slot) == "":
		return false
	if not inventory.unequip(slot):
		notice.emit("Your bag is full.")
		return false
	return true


## Uses one consumable from bag slot `index` (heal / restore MP).
func use_item(index: int) -> bool:
	var stack := inventory.get_slot(index)
	if stack.is_empty() or not is_instance_valid(player) or player.is_dead:
		return false
	var effect: Dictionary = get_item_def(stack["id"]).get("effect", {})
	var heal_amount := int(effect.get("hp", 0))
	var mp_amount := int(effect.get("mp", 0))
	if heal_amount <= 0 and mp_amount <= 0:
		return false
	var hp_full := player.hp >= player.stats.max_hp()
	var mp_full := player.mp >= player.stats.max_mp()
	if (heal_amount <= 0 or hp_full) and (mp_amount <= 0 or mp_full):
		notice.emit("Already full.")
		return false
	if heal_amount > 0:
		player.heal(heal_amount, player)
	if mp_amount > 0:
		player.restore_mp(mp_amount)
	inventory.remove_at(index, 1)
	return true


## Uses the first stack of `item_id` in the bag (for hotkeys).
func use_item_by_id(item_id: String) -> bool:
	for i in inventory.slots.size():
		if inventory.slots[i].get("id", "") == item_id:
			return use_item(i)
	return false


func move_item(from_index: int, to_index: int) -> bool:
	return inventory.move(from_index, to_index)


## Rebuilds player.stats.bonuses = base (birth sign) + gear, then clamps HP/MP.
## A character at full HP/MP stays full when a maximum goes up.
func refresh_player_bonuses() -> void:
	if not is_instance_valid(player) or player.stats == null:
		return
	var hp_was_full := player.hp >= player.stats.max_hp()
	var mp_was_full := player.mp >= player.stats.max_mp()
	player.stats.bonuses = Inventory.merge_bonuses(_base_bonuses(), inventory.gear_bonuses())
	var max_hp := player.stats.max_hp()
	var max_mp := player.stats.max_mp()
	if not player.is_dead:
		player.hp = max_hp if hp_was_full else mini(player.hp, max_hp)
	player.mp = max_mp if mp_was_full else mini(player.mp, max_mp)
	player.hp_changed.emit(player.hp, max_hp)
	player.mp_changed.emit(player.mp, max_mp)


static func rarity_color(rarity: String) -> Color:
	return RARITY_COLORS.get(rarity, RARITY_COLORS["common"])


# --- Setup helpers ---------------------------------------------------------


## Level / XP / gold from the logged-in character (Session.character).
## "xp" is treated as XP inside the current level.
func _load_character_state() -> void:
	var character: Dictionary = Session.character
	var saved_level := int(character.get("level", player.stats.level))
	if saved_level > player.stats.level:
		Leveling.apply_level_gains(player.stats, saved_level - player.stats.level, xp_curve)
	player_leveling = Leveling.new(xp_curve, player.stats.level, int(character.get("xp", 0)))
	player.stats.level = player_leveling.level
	inventory.gold = int(character.get("gold", 0))
	_last_gold = inventory.gold


func _give_starting_gear() -> void:
	if inventory.get_equipped("weapon") == "":
		inventory.equip_direct(STARTER_WEAPON)
	for item_id in STARTER_ITEMS:
		inventory.add_item(item_id, int(STARTER_ITEMS[item_id]))


func _spawn_pet() -> void:
	var def := GameData.get_entry("pets", STARTER_PET)
	if def.is_empty() or not is_instance_valid(entities_root):
		push_warning("Progression: cannot spawn starter pet '%s'" % STARTER_PET)
		return
	pet = PET_SCENE.instantiate() as Pet
	pet.setup(player, STARTER_PET, def, xp_curve)
	pet.position = entities_root.to_local(player.global_position + PET_SPAWN_OFFSET)
	entities_root.add_child(pet)
	pet.leveled_up.connect(_on_pet_leveled_up)


## Binds every progression UI already in the tree, or creates one.
func _bind_ui() -> void:
	var tree := get_tree() if is_inside_tree() else player.get_tree()
	var uis: Array = []
	if tree:
		uis = tree.get_nodes_in_group(ProgressionUI.GROUP)
	if uis.is_empty() and create_ui:
		var ui: Node = load(UI_SCENE_PATH).instantiate()
		add_child(ui)
		uis = [ui]
	for ui in uis:
		if ui.has_method("bind"):
			ui.bind(self)


# --- Runtime helpers ---------------------------------------------------------


func _base_bonuses() -> Dictionary:
	if player.has_method("get_base_bonuses"):
		var base: Variant = player.call("get_base_bonuses")
		if base is Dictionary:
			return base.duplicate()
	# Fallback (stand-in players): the birth sign passive from the session.
	var sign_id := str(Session.character.get("birth_sign", ""))
	var passive: Dictionary = GameData.get_entry("zodiac_signs", sign_id).get("passive", {})
	return passive.duplicate()


func _on_player_leveled(levels: int) -> void:
	Leveling.apply_level_gains(player.stats, levels, xp_curve)
	player.stats.level = player_leveling.level
	if not player.is_dead:
		player.heal(maxi(player.stats.max_hp() - player.hp, 0), player)
		player.restore_mp(player.stats.max_mp())
	var flash := LevelUpFlash.new()
	flash.text = "LEVEL %d!" % player_leveling.level
	player.add_child(flash)
	Events.level_up.emit(player, player_leveling.level)
	notice.emit("Level up! You are now level %d." % player_leveling.level)


func _place_pickup(pickup: LootPickup, world_pos: Vector2) -> void:
	if not is_instance_valid(entities_root):
		pickup.free()
		return
	var scatter := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.6, 0.6))
	pickup.position = entities_root.to_local(world_pos + scatter * DROP_SCATTER)
	pickup.collector = player
	pickup.collected.connect(_on_pickup_collected)
	entities_root.add_child(pickup)


func _is_player_side(killer: Node) -> bool:
	if not is_instance_valid(killer):
		return false
	return killer == player or killer.is_in_group("player") or killer.is_in_group("pets")


## Enemy data from enemies.json by `enemy_id`; falls back to `xp`, `loot_table`
## and `level` properties on the node itself (sandbox dummies, missing data).
func _enemy_data(enemy: Node) -> Dictionary:
	var id_value: Variant = enemy.get("enemy_id")
	if id_value == null:
		id_value = enemy.get_meta("enemy_id", "")
	var data := GameData.get_entry("enemies", str(id_value)).duplicate()
	if data.is_empty():
		for key in ["xp", "loot_table", "level"]:
			var value: Variant = enemy.get(key)
			if value != null:
				data[key] = value
	if not data.has("level"):
		var enemy_stats: Variant = enemy.get("stats")
		data["level"] = enemy_stats.level if enemy_stats is Stats else 1
	return data


func _sync_session() -> void:
	if Session.character.is_empty():
		return
	Session.character["level"] = get_level()
	Session.character["xp"] = get_xp()
	Session.character["gold"] = inventory.gold


# --- Signal handlers ---------------------------------------------------------


func _on_actor_died(actor: Node, killer: Node) -> void:
	if not _is_set_up or not is_instance_valid(actor) or not actor.is_in_group("enemies"):
		return
	if not _is_player_side(killer):
		return
	var data := _enemy_data(actor)
	var amount := Leveling.scaled_xp(
		int(data.get("xp", 0)), get_level(), int(data["level"]), xp_curve)
	award_xp(amount)
	if is_instance_valid(pet) and not pet.is_dead:
		pet.add_xp(PetRules.xp_share(amount, pet.xp_share))
	var table_id := str(data.get("loot_table", ""))
	if table_id != "" and actor is Node2D:
		drop_loot(table_id, (actor as Node2D).global_position)


func _on_pickup_collected(node: Node2D) -> void:
	var pickup := node as LootPickup
	if pickup == null or pickup.is_queued_for_deletion():
		return
	if pickup.is_gold():
		inventory.add_gold(pickup.gold)
		Events.item_picked_up.emit("gold", pickup.gold)
		notice.emit("+%d gold" % pickup.gold)
		pickup.queue_free()
		return
	var item_id: String = pickup.item_id
	var left := inventory.add_item(item_id, pickup.quantity)
	var taken: int = pickup.quantity - left
	var item_name := str(get_item_def(item_id).get("name", item_id))
	if taken > 0:
		Events.item_picked_up.emit(item_id, taken)
		notice.emit("+ %s x%d" % [item_name, taken] if taken > 1 else "+ %s" % item_name)
	if left == 0:
		pickup.queue_free()
		return
	pickup.setup_item(item_id, left, item_name, pickup.color)
	pickup.refuse()
	notice.emit("Your bag is full.")


func _on_inventory_changed() -> void:
	Events.inventory_changed.emit()
	if inventory.gold != _last_gold:
		_last_gold = inventory.gold
		Events.gold_changed.emit(inventory.gold)
		_sync_session()


func _on_equipment_changed(slot: String) -> void:
	refresh_player_bonuses()
	Events.equipment_changed.emit(slot)


func _on_pet_leveled_up(new_level: int) -> void:
	notice.emit("%s reached level %d!" % [pet.display_name, new_level])
	var flash := LevelUpFlash.new()
	flash.text = "LEVEL %d!" % new_level
	pet.add_child(flash)
