extends VBoxContainer
## Character creation: name + one of the 12 birth signs (from the
## zodiac_signs table: name, element, passive description). Class is fixed to
## Warrior in the MVP. The owner (login.gd) does the API call.

signal create_submitted(character_name: String, birth_sign: String)
signal back_requested

const FormField := preload("res://ui/login/form_field.gd")
const LoginTheme := preload("res://ui/login/login_theme.gd")

const GRID_COLUMNS := 4
const CARD_SIZE := Vector2(196, 92)

var _name_field: FormField
var _sign_grid: GridContainer
var _sign_group := ButtonGroup.new()
var _sign_buttons: Dictionary = {}
var _sign_error: Label
var _status: Label
var _back_button: Button
var _create_button: Button
var _selected_sign := ""
var _busy := false


func _init() -> void:
	add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = "Create a character"
	title.theme_type_variation = &"SubtitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	add_child(top)
	_name_field = FormField.new("Name", "3-16 letters or digits")
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.visible = false
	add_child(_status)

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
	_create_button.text = "Create"
	_create_button.theme_type_variation = &"AccentButton"
	_create_button.custom_minimum_size = Vector2(160, 44)
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


## Clears the form for a fresh character.
func reset() -> void:
	_name_field.set_text("")
	_name_field.set_error("")
	_set_sign_error("")
	set_status("")
	_selected_sign = ""
	for button in _sign_buttons.values():
		(button as Button).set_pressed_no_signal(false)


func focus_first() -> void:
	_name_field.focus()


func set_busy(busy: bool, message: String = "") -> void:
	_busy = busy
	_name_field.set_editable(not busy)
	_back_button.disabled = busy
	_create_button.disabled = busy
	for button in _sign_buttons.values():
		(button as Button).disabled = busy
	if busy:
		set_status(message, false)


func set_status(message: String, is_error: bool = true) -> void:
	_status.text = message
	_status.visible = message != ""
	_status.theme_type_variation = &"ErrorLabel" if is_error else &"MutedLabel"


## Displays a failed ApiResult: name / birth_sign errors inline, rest below.
func show_result(result: ApiResult) -> void:
	_name_field.set_error(result.field_error("name"))
	_set_sign_error(result.field_error("birth_sign"))
	var other: PackedStringArray = []
	for field in result.field_errors:
		if field != "name" and field != "birth_sign":
			other.append(str(result.field_errors[field]))
	if not other.is_empty():
		set_status("\n".join(other))
	elif not result.has_field_errors():
		set_status(result.error_message)
	else:
		set_status("")


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
	if _busy:
		return
	var errors := ApiRules.validate_character_form(
		_name_field.get_text(), _selected_sign, _sign_buttons.keys()
	)
	_name_field.set_error(str(errors.get("name", "")))
	_set_sign_error(str(errors.get("birth_sign", "")))
	set_status("")
	if errors.is_empty():
		create_submitted.emit(_name_field.get_text().strip_edges(), _selected_sign)
