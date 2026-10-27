extends Control
## Title screen (res://ui/title/title.tscn, routed to by scenes/boot.gd).
## Three local save slots (core/save_game.gd): an empty slot offers New Game
## (-> character name + birth sign), a filled one shows name, level, sign,
## playtime and last save time with Continue and Delete (confirmed).
## Fills Session and starts the game scene. Built in code with the login
## theme and backdrop (ui/login/login_theme.gd, login_background.gd).

const LoginTheme := preload("res://ui/login/login_theme.gd")
const LoginBackground := preload("res://ui/login/login_background.gd")
const NewGamePanel := preload("res://ui/title/new_game_panel.gd")

const GAME_SCENE := "res://scenes/game.tscn"
const SLOTS_WIDTH := 560.0

var _card: PanelContainer
var _slots_screen: VBoxContainer
var _slot_list: VBoxContainer
var _status: Label
var _new_game: NewGamePanel
var _confirm: ConfirmationDialog
var _target_slot: int = -1


func _ready() -> void:
	theme = LoginTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Coming back from the game (pause menu) leaves no game state behind.
	get_tree().paused = false
	Session.clear()
	_build_ui()
	_refresh_slots()
	_show_screen(_slots_screen)


# --- UI construction --------------------------------------------------------


func _build_ui() -> void:
	add_child(LoginBackground.new())

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	center.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Pockie Saints"
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	_card = PanelContainer.new()
	_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_card)

	_slots_screen = VBoxContainer.new()
	_slots_screen.add_theme_constant_override("separation", 12)
	_card.add_child(_slots_screen)
	var heading := Label.new()
	heading.text = "Choose a save slot"
	heading.theme_type_variation = &"SubtitleLabel"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slots_screen.add_child(heading)
	_slot_list = VBoxContainer.new()
	_slot_list.add_theme_constant_override("separation", 10)
	_slots_screen.add_child(_slot_list)
	_status = Label.new()
	_status.theme_type_variation = &"ErrorLabel"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	_slots_screen.add_child(_status)

	_new_game = NewGamePanel.new()
	_new_game.set_signs(GameData.get_table("zodiac_signs"))
	_new_game.create_submitted.connect(_on_create_submitted)
	_new_game.back_requested.connect(_show_screen.bind(_slots_screen))
	_card.add_child(_new_game)

	var hint := Label.new()
	hint.text = "Progress is saved on this device. Esc in game: pause menu."
	hint.theme_type_variation = &"MutedLabel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.6)
	column.add_child(hint)

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Delete save"
	_confirm.ok_button_text = "Delete"
	_confirm.get_ok_button().theme_type_variation = &"DangerButton"
	_confirm.confirmed.connect(_on_delete_confirmed)
	add_child(_confirm)


func _show_screen(screen: Control) -> void:
	for child in _card.get_children():
		(child as Control).visible = child == screen
	# The new game screen sizes itself from its sign grid.
	_card.custom_minimum_size = Vector2(SLOTS_WIDTH if screen == _slots_screen else 0.0, 0)
	if screen == _new_game:
		_new_game.focus_first.call_deferred()


func _refresh_slots() -> void:
	for child in _slot_list.get_children():
		_slot_list.remove_child(child)
		child.queue_free()
	for slot in range(1, SaveGame.SLOT_COUNT + 1):
		_slot_list.add_child(_build_slot_card(slot))


func _build_slot_card(slot: int) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)
	var buttons := VBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 6)
	row.add_child(buttons)

	_add_label(info, "Slot %d" % slot, &"MutedLabel")
	if not SaveGame.has_slot(slot):
		_add_label(info, "Empty", &"")
		_add_label(info, "Start a new Warrior here.", &"MutedLabel")
		_add_button(buttons, "New Game", &"AccentButton").pressed.connect(
			_on_new_game_pressed.bind(slot))
		return card

	var data := SaveGame.read_slot(slot)
	if data.is_empty():
		_add_label(info, "Damaged save", &"ErrorLabel")
		_add_label(info, "This save can't be read. Delete it to reuse the slot.", &"MutedLabel")
		_add_button(buttons, "Delete", &"DangerButton").pressed.connect(
			_on_delete_pressed.bind(slot, "the damaged save"))
		return card

	var character: Dictionary = data["character"]
	var char_name := str(character["name"])
	var sign_entry := GameData.get_entry("zodiac_signs", str(character["birth_sign"]))
	var sign_name := str(sign_entry.get("name", str(character["birth_sign"]).capitalize()))
	var name_label := _add_label(info, char_name, &"")
	name_label.add_theme_color_override("font_color", LoginTheme.GOLD)
	name_label.add_theme_font_size_override("font_size", 20)
	_add_label(info, "Level %d Warrior  -  %s" % [int(character["level"]), sign_name], &"")
	_add_label(info, "Played %s  -  Saved %s" % [
		format_playtime(float(data["playtime"])), format_saved_at(int(data["saved_at"]))],
		&"MutedLabel")
	_add_button(buttons, "Continue", &"AccentButton").pressed.connect(
		_on_continue_pressed.bind(slot))
	_add_button(buttons, "Delete", &"DangerButton").pressed.connect(
		_on_delete_pressed.bind(slot, char_name))
	return card


func _add_label(parent: Control, text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	if variation != &"":
		label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _add_button(parent: Control, text: String, variation: StringName) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	button.custom_minimum_size = Vector2(130, 38)
	parent.add_child(button)
	return button


func _set_status(message: String) -> void:
	_status.text = message
	_status.visible = message != ""


# --- Formatting -----------------------------------------------------------------


## "1h 05m", "12m 30s" or "45s".
static func format_playtime(seconds: float) -> String:
	var total := maxi(int(seconds), 0)
	var hours := floori(total / 3600.0)
	var minutes := floori((total % 3600) / 60.0)
	if hours > 0:
		return "%dh %02dm" % [hours, minutes]
	if minutes > 0:
		return "%dm %02ds" % [minutes, total % 60]
	return "%ds" % total


## Local date and time of a unix timestamp, "never" for 0.
static func format_saved_at(unix_time: int) -> String:
	if unix_time <= 0:
		return "never"
	var bias_minutes := int(Time.get_time_zone_from_system().get("bias", 0))
	var local := Time.get_datetime_dict_from_unix_time(unix_time + bias_minutes * 60)
	return "%04d-%02d-%02d %02d:%02d" % [
		local["year"], local["month"], local["day"], local["hour"], local["minute"]]


# --- Actions ------------------------------------------------------------------


func _on_new_game_pressed(slot: int) -> void:
	_target_slot = slot
	_set_status("")
	_new_game.reset(slot)
	_show_screen(_new_game)


func _on_create_submitted(character_name: String, birth_sign: String) -> void:
	if not SaveGame.is_valid_slot(_target_slot):
		_show_screen(_slots_screen)
		return
	Session.start_new_game(_target_slot, character_name, birth_sign)
	_start_game()


func _on_continue_pressed(slot: int) -> void:
	var data := SaveGame.read_slot(slot)
	if data.is_empty():
		_set_status("Slot %d could not be loaded." % slot)
		_refresh_slots()
		return
	Session.start_from_save(slot, data)
	_start_game()


func _on_delete_pressed(slot: int, label: String) -> void:
	_target_slot = slot
	_confirm.dialog_text = "Delete %s in slot %d?\nThis cannot be undone." % [label, slot]
	_confirm.popup_centered()


func _on_delete_confirmed() -> void:
	var err := SaveGame.delete_slot(_target_slot)
	if err != OK:
		_set_status("Could not delete slot %d (error %d)." % [_target_slot, err])
	else:
		_set_status("")
	_target_slot = -1
	_refresh_slots()


func _start_game() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)
