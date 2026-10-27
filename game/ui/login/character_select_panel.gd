extends VBoxContainer
## Character select: up to ApiRules.MAX_CHARACTERS rows (name, level, sign)
## with Play / Delete, plus Create New and Log out. Delete asks for
## confirmation first. The owner (login.gd) does the API calls.

signal play_requested(character: Dictionary)
signal delete_requested(character: Dictionary)
signal create_requested
signal logout_requested

var _account_label: Label
var _slots_label: Label
var _list: VBoxContainer
var _empty_label: Label
var _status: Label
var _create_button: Button
var _logout_button: Button
var _confirm: ConfirmationDialog
var _pending_delete: Dictionary = {}
var _row_buttons: Array[Button] = []
var _character_count := 0
var _busy := false


func _init() -> void:
	add_theme_constant_override("separation", 14)
	custom_minimum_size = Vector2(560, 0)

	var title := Label.new()
	title.text = "Choose your character"
	title.theme_type_variation = &"SubtitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	_account_label = Label.new()
	_account_label.theme_type_variation = &"MutedLabel"
	_account_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_account_label)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	add_child(_list)

	_empty_label = Label.new()
	_empty_label.text = "No characters yet. Create one to start your journey."
	_empty_label.theme_type_variation = &"MutedLabel"
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_empty_label)

	_slots_label = Label.new()
	_slots_label.theme_type_variation = &"MutedLabel"
	_slots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_slots_label)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.visible = false
	add_child(_status)

	add_child(HSeparator.new())

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	add_child(footer)
	_logout_button = Button.new()
	_logout_button.text = "Log out"
	_logout_button.pressed.connect(func() -> void: logout_requested.emit())
	footer.add_child(_logout_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_create_button = Button.new()
	_create_button.text = "Create new"
	_create_button.theme_type_variation = &"AccentButton"
	_create_button.custom_minimum_size = Vector2(160, 44)
	_create_button.pressed.connect(func() -> void: create_requested.emit())
	footer.add_child(_create_button)

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Delete character"
	_confirm.ok_button_text = "Delete"
	_confirm.dialog_autowrap = true
	_confirm.min_size = Vector2i(380, 0)
	_confirm.confirmed.connect(_on_delete_confirmed)
	add_child(_confirm)


func set_account_name(username: String) -> void:
	_account_label.text = "Logged in as %s" % username if username != "" else ""
	_account_label.visible = username != ""


## Rebuilds the rows. `characters` are normalized API character dictionaries,
## `signs` the zodiac_signs table (for display names).
func set_characters(characters: Array[Dictionary], signs: Dictionary) -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_row_buttons.clear()
	_character_count = characters.size()
	for character in characters:
		_list.add_child(_build_row(character, signs))
	_empty_label.visible = characters.is_empty()
	_list.visible = not characters.is_empty()
	_slots_label.text = "%d / %d character slots used" % [
		_character_count, ApiRules.MAX_CHARACTERS
	]
	_update_buttons()


func set_busy(busy: bool, message: String = "") -> void:
	_busy = busy
	_update_buttons()
	if busy:
		set_status(message, false)


func set_status(message: String, is_error: bool = true) -> void:
	_status.text = message
	_status.visible = message != ""
	_status.theme_type_variation = &"ErrorLabel" if is_error else &"MutedLabel"


## One-line summary such as "Level 3 Warrior  ·  Leo (fire)".
static func describe(character: Dictionary, signs: Dictionary) -> String:
	var sign_id := str(character.get("birth_sign", ""))
	var sign_entry: Dictionary = signs.get(sign_id, {})
	var sign_text := str(sign_entry.get("name", sign_id.capitalize()))
	if sign_entry.has("element"):
		sign_text += " (%s)" % str(sign_entry["element"])
	return "Level %d %s  ·  %s" % [
		int(character.get("level", 1)), str(character.get("class", "warrior")).capitalize(), sign_text
	]


func _build_row(character: Dictionary, signs: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)
	var name_label := Label.new()
	name_label.text = str(character.get("name", "?"))
	name_label.theme_type_variation = &"SubtitleLabel"
	info.add_child(name_label)
	var detail := Label.new()
	detail.text = describe(character, signs)
	detail.theme_type_variation = &"MutedLabel"
	info.add_child(detail)

	var delete_button := Button.new()
	delete_button.text = "Delete"
	delete_button.theme_type_variation = &"DangerButton"
	delete_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	delete_button.pressed.connect(_ask_delete.bind(character))
	row.add_child(delete_button)

	var play_button := Button.new()
	play_button.text = "Play"
	play_button.theme_type_variation = &"AccentButton"
	play_button.custom_minimum_size = Vector2(110, 44)
	play_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	play_button.pressed.connect(func() -> void: play_requested.emit(character))
	row.add_child(play_button)

	_row_buttons.append(delete_button)
	_row_buttons.append(play_button)
	return card


func _update_buttons() -> void:
	for button in _row_buttons:
		button.disabled = _busy
	_logout_button.disabled = _busy
	_create_button.disabled = _busy or _character_count >= ApiRules.MAX_CHARACTERS
	_create_button.tooltip_text = (
		"All %d slots are used." % ApiRules.MAX_CHARACTERS
		if _character_count >= ApiRules.MAX_CHARACTERS else ""
	)


func _ask_delete(character: Dictionary) -> void:
	if _busy:
		return
	_pending_delete = character
	_confirm.dialog_text = (
		"Delete %s for good? This cannot be undone." % str(character.get("name", "this character"))
	)
	_confirm.popup_centered()


func _on_delete_confirmed() -> void:
	if not _pending_delete.is_empty():
		delete_requested.emit(_pending_delete)
	_pending_delete = {}
