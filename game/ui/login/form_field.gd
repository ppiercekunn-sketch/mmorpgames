extends VBoxContainer
## A labelled LineEdit with an inline error message underneath.
## Emits `submitted` when Enter is pressed inside the field.

signal submitted

var caption: Label
var input: LineEdit
var error_label: Label


func _init(caption_text: String, placeholder: String = "", secret: bool = false) -> void:
	add_theme_constant_override("separation", 4)

	caption = Label.new()
	caption.text = caption_text
	caption.theme_type_variation = &"MutedLabel"
	add_child(caption)

	input = LineEdit.new()
	input.placeholder_text = placeholder
	input.secret = secret
	input.custom_minimum_size = Vector2(0, 40)
	input.text_submitted.connect(func(_text: String) -> void: submitted.emit())
	input.text_changed.connect(func(_text: String) -> void: set_error(""))
	add_child(input)

	error_label = Label.new()
	error_label.theme_type_variation = &"ErrorLabel"
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.visible = false
	add_child(error_label)


func get_text() -> String:
	return input.text


func set_text(value: String) -> void:
	input.text = value


func set_error(message: String) -> void:
	error_label.text = message
	error_label.visible = message != ""


func set_editable(editable: bool) -> void:
	input.editable = editable


## Focuses the input once it is visible (safe to call while hidden).
func focus() -> void:
	if input.is_visible_in_tree():
		input.grab_focus()
