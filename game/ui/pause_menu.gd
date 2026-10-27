extends CanvasLayer
## In-game pause menu (created by scenes/game.gd). Esc toggles it; while open
## the scene tree is paused. Buttons: Resume / Save / Quit to title. The owner
## connects `save_requested` and `quit_requested` and reports save results
## with show_status(). Uses the login theme (ui/login/login_theme.gd).
##
## game.gd adds this node before the other systems, so their
## _unhandled_input (e.g. Esc closing the inventory window) runs first.

signal save_requested
signal quit_requested

const LoginTheme := preload("res://ui/login/login_theme.gd")

## False for unsaved (`--offline`) games: the Save button is disabled.
var can_save: bool = true:
	set(value):
		can_save = value
		if _save_button:
			_save_button.disabled = not value
			_save_button.tooltip_text = "" if value else "This game has no save slot."

var _root: Control
var _resume_button: Button
var _save_button: Button
var _quit_button: Button
var _status: Label


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	can_save = can_save
	visible = false


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	visible = true
	set_status("")
	get_tree().paused = true
	_resume_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false


func set_status(message: String, is_error: bool = false) -> void:
	_status.text = message
	_status.visible = message != ""
	_status.theme_type_variation = &"ErrorLabel" if is_error else &"MutedLabel"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_root = Control.new()
	_root.theme = LoginTheme.build()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(LoginTheme.NAVY_DARK, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow clicks meant for the world
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var title := Label.new()
	title.text = "Paused"
	title.theme_type_variation = &"SubtitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	_resume_button = _add_button(column, "Resume", &"AccentButton")
	_resume_button.pressed.connect(close)
	_save_button = _add_button(column, "Save", &"")
	_save_button.pressed.connect(func() -> void: save_requested.emit())
	_quit_button = _add_button(column, "Quit to title", &"")
	_quit_button.pressed.connect(func() -> void: quit_requested.emit())

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	column.add_child(_status)


func _add_button(parent: Control, text: String, variation: StringName) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 44)
	if variation != &"":
		button.theme_type_variation = variation
	parent.add_child(button)
	return button
