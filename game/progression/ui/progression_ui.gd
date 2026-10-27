class_name ProgressionUI
extends CanvasLayer
## Progression HUD: XP bar + level (bottom), gold, pickup notices, pet frame,
## and the inventory / equipment window (toggle with `toggle_inventory`, I).
## Built in code. Progression binds it during setup(); if this scene is
## instanced separately it finds the Progression node (group "progression").
## Bag slot: left/right click = equip or use. Equipment slot: click = unequip.

const GROUP := "progression_ui"
const SLOT_SIZE := Vector2(52, 52)
const BAG_COLUMNS := 6
const NOTICE_SECONDS := 3.5
const MAX_NOTICES := 5
const SLOT_LABELS := {
	"weapon": "Weapon", "head": "Head", "body": "Body", "feet": "Feet", "ring": "Ring",
}

var progression: Progression

var _xp_bar: ProgressBar
var _level_label: Label
var _gold_label: Label
var _notice_label: Label
var _notices: Array[Dictionary] = []
var _flash: ColorRect
var _window: PanelContainer
var _bag_buttons: Array[Button] = []
var _equip_buttons: Dictionary = {}
var _stats_label: Label
var _window_gold_label: Label
var _pet_frame: PanelContainer
var _pet_label: Label
var _pet_hp_bar: ProgressBar
var _bound_pet: Pet
var _is_duplicate: bool = false


func _enter_tree() -> void:
	# Only one progression UI at a time (it may be both auto-created and instanced).
	for other in get_tree().get_nodes_in_group(GROUP):
		if other != self:
			_is_duplicate = true
			queue_free()
			return
	add_to_group(GROUP)


func _ready() -> void:
	if _is_duplicate:
		return
	layer = 5
	_build_hud()
	_build_window()
	_build_pet_frame()
	Events.xp_gained.connect(_on_xp_changed)
	Events.level_up.connect(_on_level_up)
	Events.gold_changed.connect(_on_gold_changed)
	Events.inventory_changed.connect(_refresh_window)
	Events.equipment_changed.connect(_on_equipment_changed)
	if progression == null:
		_find_progression.call_deferred()


## Connects the UI to a set-up Progression node.
func bind(p: Progression) -> void:
	if _is_duplicate or progression == p:
		return
	progression = p
	if not p.notice.is_connected(show_notice):
		p.notice.connect(show_notice)
	if is_instance_valid(p.player):
		p.player.hp_changed.connect(_on_player_vitals_changed)
		p.player.mp_changed.connect(_on_player_vitals_changed)
	_bind_pet(p.pet)
	_refresh_all()


func toggle_inventory() -> void:
	_window.visible = not _window.visible
	if _window.visible:
		_refresh_window()


func show_notice(text: String) -> void:
	_notices.append({"text": text, "t": NOTICE_SECONDS})
	while _notices.size() > MAX_NOTICES:
		_notices.pop_front()
	_update_notice_label()


func _unhandled_input(event: InputEvent) -> void:
	if _is_duplicate:
		return
	if event.is_action_pressed("toggle_inventory"):
		toggle_inventory()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and _window.visible:
		_window.visible = false
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _notices.is_empty():
		return
	var expired := false
	for entry in _notices:
		entry["t"] = float(entry["t"]) - delta
		expired = expired or float(entry["t"]) <= 0.0
	if expired:
		_notices.assign(_notices.filter(func(e: Dictionary) -> bool: return float(e["t"]) > 0.0))
		_update_notice_label()


func _find_progression() -> void:
	for node in get_tree().get_nodes_in_group(Progression.GROUP):
		var p := node as Progression
		if p and p.is_set_up():
			bind(p)
			return


# --- Building --------------------------------------------------------------


func _build_hud() -> void:
	_flash = ColorRect.new()
	_flash.color = Color(1.0, 0.85, 0.35, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_anchors(_flash, 0, 0, 1, 1)
	add_child(_flash)

	_xp_bar = ProgressBar.new()
	_xp_bar.show_percentage = false
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_bar.add_theme_stylebox_override("background", _box(Color(0.08, 0.06, 0.12, 0.85)))
	_xp_bar.add_theme_stylebox_override("fill", _box(Color(0.62, 0.42, 1.0)))
	_set_anchors(_xp_bar, 0, 1, 1, 1)
	_xp_bar.offset_top = -10
	add_child(_xp_bar)

	_level_label = _make_label(14)
	_set_anchors(_level_label, 0, 1, 0, 1)
	_level_label.offset_left = 10
	_level_label.offset_top = -32
	_level_label.offset_right = 400
	_level_label.offset_bottom = -12
	add_child(_level_label)

	_gold_label = _make_label(14)
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_set_anchors(_gold_label, 1, 1, 1, 1)
	_gold_label.offset_left = -300
	_gold_label.offset_top = -32
	_gold_label.offset_right = -10
	_gold_label.offset_bottom = -12
	add_child(_gold_label)

	_notice_label = _make_label(13)
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_notice_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_set_anchors(_notice_label, 1, 1, 1, 1)
	_notice_label.offset_left = -360
	_notice_label.offset_top = -150
	_notice_label.offset_right = -10
	_notice_label.offset_bottom = -36
	add_child(_notice_label)


func _build_window() -> void:
	_window = PanelContainer.new()
	_window.visible = false
	_window.add_theme_stylebox_override("panel", _box(Color(0.1, 0.1, 0.16, 0.95), 2))
	_set_anchors(_window, 0.5, 0.5, 0.5, 0.5)
	_window.offset_left = -340
	_window.offset_right = 340
	_window.offset_top = -230
	_window.offset_bottom = 210
	add_child(_window)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	_window.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := _make_label(16)
	title.text = "Inventory  (I)"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_window_gold_label = _make_label(14)
	_window_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	header.add_child(_window_gold_label)
	var close := Button.new()
	close.text = " X "
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(toggle_inventory)
	header.add_child(close)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	root.add_child(body)
	body.add_child(_build_equipment_column())
	body.add_child(_build_bag_grid())


func _build_equipment_column() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(250, 0)
	var heading := _make_label(13)
	heading.text = "Equipment (click to unequip)"
	column.add_child(heading)
	for slot in Inventory.EQUIP_SLOTS:
		var row := HBoxContainer.new()
		var name_label := _make_label(12)
		name_label.text = SLOT_LABELS.get(slot, slot)
		name_label.custom_minimum_size = Vector2(56, 0)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_label)
		var button := _make_slot_button()
		button.gui_input.connect(_on_equip_slot_input.bind(slot))
		row.add_child(button)
		column.add_child(row)
		_equip_buttons[slot] = button
	_stats_label = _make_label(12)
	column.add_child(_stats_label)
	return column


func _build_bag_grid() -> Control:
	var column := VBoxContainer.new()
	var heading := _make_label(13)
	heading.text = "Bag (click: equip / use)"
	column.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = BAG_COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	column.add_child(grid)
	for i in Inventory.DEFAULT_SIZE:
		var button := _make_slot_button()
		button.gui_input.connect(_on_bag_slot_input.bind(i))
		grid.add_child(button)
		_bag_buttons.append(button)
	return column


func _build_pet_frame() -> void:
	_pet_frame = PanelContainer.new()
	_pet_frame.visible = false
	_pet_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pet_frame.add_theme_stylebox_override("panel", _box(Color(0.1, 0.1, 0.16, 0.8), 1))
	_pet_frame.position = Vector2(12, 120)
	_pet_frame.custom_minimum_size = Vector2(170, 0)
	add_child(_pet_frame)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pet_frame.add_child(column)
	_pet_label = _make_label(12)
	column.add_child(_pet_label)
	_pet_hp_bar = ProgressBar.new()
	_pet_hp_bar.show_percentage = false
	_pet_hp_bar.custom_minimum_size = Vector2(150, 8)
	_pet_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pet_hp_bar.add_theme_stylebox_override("background", _box(Color(0.2, 0.05, 0.05)))
	_pet_hp_bar.add_theme_stylebox_override("fill", _box(Color(0.4, 0.85, 0.4)))
	column.add_child(_pet_hp_bar)


func _make_slot_button() -> Button:
	var button := Button.new()
	button.custom_minimum_size = SLOT_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = true
	var item_name := _make_label(9)
	item_name.name = "ItemName"
	item_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_set_anchors(item_name, 0, 0, 1, 1)
	button.add_child(item_name)
	var qty := _make_label(10)
	qty.name = "Qty"
	qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	qty.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_set_anchors(qty, 0, 0, 1, 1)
	qty.offset_right = -3
	button.add_child(qty)
	_style_slot(button, Color(0.18, 0.18, 0.24), false)
	return button


# --- Refreshing ------------------------------------------------------------


func _refresh_all() -> void:
	_refresh_xp()
	_on_gold_changed(progression.inventory.gold if progression else 0)
	_refresh_window()
	_refresh_pet()


func _refresh_xp() -> void:
	if progression == null:
		return
	var to_next := progression.get_xp_to_next()
	if to_next <= 0:
		_xp_bar.max_value = 1
		_xp_bar.value = 1
		_level_label.text = "Lv %d   MAX" % progression.get_level()
	else:
		_xp_bar.max_value = to_next
		_xp_bar.value = progression.get_xp()
		_level_label.text = "Lv %d   %d / %d XP" % [
			progression.get_level(), progression.get_xp(), to_next]


func _refresh_window() -> void:
	if progression == null or progression.inventory == null or not _window.visible:
		return
	var inv := progression.inventory
	for i in _bag_buttons.size():
		var stack := inv.get_slot(i)
		if stack.is_empty():
			_show_slot(_bag_buttons[i], "", 0)
		else:
			_show_slot(_bag_buttons[i], stack["id"], int(stack["qty"]))
	for slot in _equip_buttons:
		_show_slot(_equip_buttons[slot], inv.get_equipped(slot), 1)
	_window_gold_label.text = "%d gold   " % inv.gold
	_refresh_stats()


func _show_slot(button: Button, item_id: String, qty: int) -> void:
	var name_label: Label = button.get_node("ItemName")
	var qty_label: Label = button.get_node("Qty")
	if item_id == "":
		name_label.text = ""
		qty_label.text = ""
		button.tooltip_text = ""
		_style_slot(button, Color(0.18, 0.18, 0.24), false)
		return
	var def := progression.get_item_def(item_id)
	name_label.text = str(def.get("name", item_id))
	qty_label.text = str(qty) if qty > 1 else ""
	button.tooltip_text = describe_item(def)
	_style_slot(button, Progression.rarity_color(str(def.get("rarity", "common"))), true)


func _refresh_stats() -> void:
	var p := progression.player
	if not is_instance_valid(p) or p.stats == null:
		_stats_label.text = ""
		return
	var s := p.stats
	_stats_label.text = "\n".join([
		"Level %d" % s.level,
		"HP %d / %d    MP %d / %d" % [p.hp, s.max_hp(), p.mp, s.max_mp()],
		"Attack %d    Defense %d" % [s.attack(), s.defense()],
		"Crit %.1f%%    Speed %d" % [s.crit_chance() * 100.0, int(s.move_speed())],
		"STR %d  AGI %d  INT %d  VIT %d" % [s.strength, s.agility, s.intellect, s.vitality],
	])


func _refresh_pet() -> void:
	var pet := _bound_pet
	if not is_instance_valid(pet) or pet.stats == null:
		_pet_frame.visible = false
		return
	_pet_frame.visible = true
	var state := "  (respawning)" if pet.is_dead else ""
	_pet_label.text = "%s  Lv %d%s\nHP %d / %d" % [
		pet.display_name, pet.get_level(), state, pet.hp, pet.stats.max_hp()]
	_pet_hp_bar.max_value = maxi(pet.stats.max_hp(), 1)
	_pet_hp_bar.value = pet.hp


func _bind_pet(pet: Pet) -> void:
	_bound_pet = pet
	if not is_instance_valid(pet):
		return
	pet.hp_changed.connect(_on_pet_hp_changed)
	pet.died.connect(_on_pet_died)
	pet.respawned.connect(_refresh_pet)
	pet.leveled_up.connect(_on_pet_leveled_up)


func _update_notice_label() -> void:
	var lines: Array[String] = []
	for entry in _notices:
		lines.append(str(entry["text"]))
	_notice_label.text = "\n".join(lines)


## Tooltip text for an item: name, rarity/slot, stat bonuses, effect, description.
static func describe_item(def: Dictionary) -> String:
	var lines: Array[String] = [str(def.get("name", "?"))]
	var kind := str(def.get("type", ""))
	var rarity := str(def.get("rarity", "common")).capitalize()
	if kind == "equipment":
		lines.append("%s %s  (level %d)" % [
			rarity, str(def.get("slot", "")).capitalize(), int(def.get("level_req", 1))])
	else:
		lines.append("%s %s" % [rarity, kind.capitalize()])
	var bonuses: Dictionary = def.get("bonuses", {})
	for key in bonuses:
		lines.append(format_bonus(key, float(bonuses[key])))
	var effect: Dictionary = def.get("effect", {})
	if effect.has("hp"):
		lines.append("Restores %d HP" % int(effect["hp"]))
	if effect.has("mp"):
		lines.append("Restores %d MP" % int(effect["mp"]))
	if def.has("description"):
		lines.append(str(def["description"]))
	return "\n".join(lines)


static func format_bonus(key: String, value: float) -> String:
	var label := key.replace("_", " ").capitalize()
	if key == "crit_chance":
		return "%+.0f%% Crit Chance" % (value * 100.0)
	return "%+d %s" % [int(value), label]


# --- Small helpers ---------------------------------------------------------


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 3)
	return label


func _set_anchors(control: Control, left: float, top: float, right: float, bottom: float) -> void:
	control.anchor_left = left
	control.anchor_top = top
	control.anchor_right = right
	control.anchor_bottom = bottom
	control.offset_left = 0
	control.offset_top = 0
	control.offset_right = 0
	control.offset_bottom = 0


func _box(color: Color, border: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	if border > 0:
		box.set_border_width_all(border)
		box.border_color = Color(0.45, 0.4, 0.65)
	box.set_corner_radius_all(3)
	return box


func _style_slot(button: Button, color: Color, filled: bool) -> void:
	var normal := _box(color.darkened(0.55) if filled else color, 2)
	normal.border_color = color if filled else Color(0.3, 0.3, 0.4)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = normal.bg_color.lightened(0.15)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


# --- Signal handlers -------------------------------------------------------


func _on_bag_slot_input(event: InputEvent, index: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or progression == null:
		return
	if click.button_index == MOUSE_BUTTON_LEFT or click.button_index == MOUSE_BUTTON_RIGHT:
		progression.activate_slot(index)
		get_viewport().set_input_as_handled()


func _on_equip_slot_input(event: InputEvent, slot: String) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or progression == null:
		return
	if click.button_index == MOUSE_BUTTON_LEFT or click.button_index == MOUSE_BUTTON_RIGHT:
		progression.unequip(slot)
		get_viewport().set_input_as_handled()


func _on_xp_changed(actor: Node, _amount: int) -> void:
	if progression and actor == progression.player:
		_refresh_xp()


func _on_level_up(actor: Node, new_level: int) -> void:
	if progression == null or actor != progression.player:
		return
	_refresh_xp()
	_refresh_window()
	_flash.color.a = 0.0
	var tween := create_tween()
	tween.tween_property(_flash, "color:a", 0.35, 0.12)
	tween.tween_property(_flash, "color:a", 0.0, 0.7)
	show_notice("Level %d!" % new_level)


func _on_gold_changed(new_total: int) -> void:
	_gold_label.text = "%d gold" % new_total
	if _window.visible:
		_window_gold_label.text = "%d gold   " % new_total


func _on_equipment_changed(_slot: String) -> void:
	_refresh_window()


func _on_player_vitals_changed(_current: int, _maximum: int) -> void:
	if _window.visible:
		_refresh_stats()


func _on_pet_hp_changed(_current: int, _maximum: int) -> void:
	_refresh_pet()


func _on_pet_died(_killer: Node) -> void:
	_refresh_pet()


func _on_pet_leveled_up(_new_level: int) -> void:
	_refresh_pet()
