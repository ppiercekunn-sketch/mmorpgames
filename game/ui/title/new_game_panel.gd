extends VBoxContainer
## New game: character name + one of the 12 birth signs (zodiac_signs table:
## name, element, passive description). Class is fixed to Warrior in the MVP.
## Local version of ui/login/character_create_panel.gd (no API); validation
## is SaveGame.validate_character_name(). The owner (title.gd) starts the game.

signal create_submitted(character_name: String, birth_sign: String)
signal back_requested

const FormField := preload("res://ui/login/form_field.gd")
const LoginTheme := preload("res://ui/login/login_theme.gd")

const GRID_COLUMNS := 4
const CARD_SIZE := Vector2(196, 92)

var _title: Label
var _name_field: FormField
var _sign_grid: GridContainer
var _sign_group := ButtonGroup.new()
var _sign_buttons: Dictionary = {}
var _sign_error: Label
var _back_button: Button
var _create_button: Button
var _selected_sign := ""


func _init() -> void:
	add_theme_constant_override("separation", 12)

	_title = Label.new()
	_title.text = "New game"
	_title.theme_type_variation = &"SubtitleLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	add_child(top)
	_name_field = FormField.new("Name", "3-16 letters or digits")
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_field.input.max_length = SaveGame.NAME_MAX
	_name_field.submitted.connect(_submit)
	top.add_child(_name_field)
	var class_box := VBoxContainer.new()
	class_box.add_theme_constant_override("separation", 4)
	top.add_child(class_box)
	var class_caption := Label.new()
	class_caption.text = "Class"
	class_caption.theme_type_variation = &"MutedLabel"
	class_box.add_child(class_caption)
	var class_label := Label.new()
	class_label.text = "Warrior"
	class_label.custom_minimum_size = Vector2(0, 40)
	class_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	class_box.add_child(class_label)

	var sign_caption := Label.new()
	sign_caption.text = "Birth sign (grants a passive bonus)"
	sign_caption.theme_type_variation = &"MutedLabel"
	add_child(sign_caption)

	_sign_grid = GridContainer.new()
	_sign_grid.columns = GRID_COLUMNS
	_sign_grid.add_theme_constant_override("h_separation", 8)
	_sign_grid.add_theme_constant_override("v_separation", 8)
	add_child(_sign_grid)

	_sign_error = Label.new()
	_sign_error.theme_type_variation = &"ErrorLabel"
	_sign_error.visible = false
	add_child(_sign_error)

	var footer := HBoxContainer.new()
	add_child(footer)
	_back_button = Button.new()
	_back_button.text = "Back"
	_back_button.pressed.connect(func() -> void: back_requested.emit())
	footer.add_child(_back_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_create_button = Button.new()
	_create_button.text = "Start adventure"
	_create_button.theme_type_variation = &"AccentButton"
	_create_button.custom_minimum_size = Vector2(180, 44)
	_create_button.pressed.connect(_submit)
	footer.add_child(_create_button)


## Builds one card per sign, in table order. `signs` is the zodiac_signs table.
func set_signs(signs: Dictionary) -> void:
	for child in _sign_grid.get_children():
		_sign_grid.remove_child(child)
		child.queue_free()
	_sign_buttons.clear()
	for sign_id in signs:
		var card := _build_sign_card(str(sign_id), signs[sign_id])
		_sign_grid.add_child(card)
		_sign_buttons[str(sign_id)] = card


## Clears the form for a fresh character in save slot `slot`.
func reset(slot: int) -> void:
	_title.text = "New game - slot %d" % slot
	_name_field.set_text("")
	_name_field.set_error("")
	_set_sign_error("")
	_selected_sign = ""
	for button in _sign_buttons.values():
		(button as Button).set_pressed_no_signal(false)


func focus_first() -> void:
	_name_field.focus()


func _build_sign_card(sign_id: String, entry: Dictionary) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.button_group = _sign_group
	button.theme_type_variation = &"SignCard"
	button.custom_minimum_size = CARD_SIZE
	button.tooltip_text = str(entry.get("description", ""))
	button.toggled.connect(_on_sign_toggled.bind(sign_id))

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	button.add_child(margin)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	margin.add_child(box)

	var element := str(entry.get("element", ""))
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(header)
	var name_label := _card_label(str(entry.get("name", sign_id.capitalize())), 17)
	name_label.add_theme_color_override("font_color", LoginTheme.GOLD)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)
	var element_label := _card_label(element.capitalize(), 13)
	element_label.add_theme_color_override("font_color", LoginTheme.element_color(element))
	header.add_child(element_label)

	var description := _card_label(str(entry.get("description", "")), 13)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", LoginTheme.TEXT)
	box.add_child(description)
	return button


func _card_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _on_sign_toggled(pressed: bool, sign_id: String) -> void:
	if pressed:
		_selected_sign = sign_id
		_set_sign_error("")


func _set_sign_error(message: String) -> void:
	_sign_error.text = message
	_sign_error.visible = message != ""


func _submit() -> void:
	var character_name := _name_field.get_text().strip_edges()
	var name_error := SaveGame.validate_character_name(character_name)
	var sign_error := ""
	if _selected_sign == "" or not _sign_buttons.has(_selected_sign):
		sign_error = "Pick a birth sign."
	_name_field.set_error(name_error)
	_set_sign_error(sign_error)
	if name_error == "" and sign_error == "":
		create_submitted.emit(character_name, _selected_sign)
