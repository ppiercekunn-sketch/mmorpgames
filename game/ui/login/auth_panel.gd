extends VBoxContainer
## Login / Register tabs plus the "Play offline" button.
## Validates input client-side (ApiRules), then emits a signal; the owner
## (login.gd) does the API call and reports back with show_result().

signal login_submitted(login_name: String, password: String)
signal register_submitted(username: String, email: String, password: String, confirmation: String)
signal offline_requested

const FormField := preload("res://ui/login/form_field.gd")

const TAB_LOGIN := 0
const TAB_REGISTER := 1

var _tabs: TabContainer
var _login_field: FormField
var _password_field: FormField
var _login_button: Button
var _reg_username: FormField
var _reg_email: FormField
var _reg_password: FormField
var _reg_confirm: FormField
var _register_button: Button
var _offline_button: Button
var _status: Label
var _busy := false


func _init() -> void:
	add_theme_constant_override("separation", 14)
	custom_minimum_size = Vector2(420, 0)

	_tabs = TabContainer.new()
	_tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	add_child(_tabs)
	_tabs.add_child(_build_login_tab())
	_tabs.add_child(_build_register_tab())
	_tabs.set_tab_title(TAB_LOGIN, "Log in")
	_tabs.set_tab_title(TAB_REGISTER, "Register")
	_tabs.tab_changed.connect(_on_tab_changed)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.visible = false
	add_child(_status)

	add_child(HSeparator.new())

	_offline_button = Button.new()
	_offline_button.text = "Play offline"
	_offline_button.tooltip_text = "No server needed. Progress is not saved."
	_offline_button.pressed.connect(func() -> void: offline_requested.emit())
	add_child(_offline_button)

	var hint := Label.new()
	hint.text = "Offline play needs no account; progress is not saved."
	hint.theme_type_variation = &"MutedLabel"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)


## Pre-fills the login field (remembered username) and focuses the right input.
func set_last_username(username: String) -> void:
	_login_field.set_text(username)


func focus_first() -> void:
	if _tabs.current_tab == TAB_REGISTER:
		_reg_username.focus()
	elif _login_field.get_text() == "":
		_login_field.focus()
	else:
		_password_field.focus()


func set_busy(busy: bool, message: String = "") -> void:
	_busy = busy
	for field in _all_fields():
		field.set_editable(not busy)
	_login_button.disabled = busy
	_register_button.disabled = busy
	_offline_button.disabled = busy
	for tab in _tabs.get_tab_count():
		_tabs.set_tab_disabled(tab, busy and tab != _tabs.current_tab)
	if busy:
		set_status(message, false)


## Shows a general message under the form ("" hides it).
func set_status(message: String, is_error: bool = true) -> void:
	_status.text = message
	_status.visible = message != ""
	_status.theme_type_variation = &"ErrorLabel" if is_error else &"MutedLabel"


## Displays a failed ApiResult: field errors under their inputs, the rest below.
func show_result(result: ApiResult) -> void:
	var by_field := _current_field_map()
	var unmatched: PackedStringArray = []
	for field in result.field_errors:
		if by_field.has(field):
			(by_field[field] as FormField).set_error(result.field_errors[field])
		else:
			unmatched.append(str(result.field_errors[field]))
	if unmatched.is_empty():
		set_status(result.error_message if not result.has_field_errors() else "")
	else:
		set_status("\n".join(unmatched))


func clear_password_fields() -> void:
	_password_field.set_text("")
	_reg_password.set_text("")
	_reg_confirm.set_text("")


func _build_login_tab() -> Control:
	var box := _tab_box()
	_login_field = FormField.new("Username or email", "alice")
	_password_field = FormField.new("Password", "", true)
	_login_field.submitted.connect(_password_field.focus)
	_password_field.submitted.connect(_submit_login)
	box.add_child(_login_field)
	box.add_child(_password_field)
	_login_button = _accent_button("Log in", _submit_login)
	box.add_child(_login_button)
	return box


func _build_register_tab() -> Control:
	var box := _tab_box()
	_reg_username = FormField.new("Username", "3-20 letters, digits or _")
	_reg_email = FormField.new("Email", "you@example.com")
	_reg_password = FormField.new("Password", "At least 8 characters", true)
	_reg_confirm = FormField.new("Confirm password", "", true)
	_reg_username.submitted.connect(_reg_email.focus)
	_reg_email.submitted.connect(_reg_password.focus)
	_reg_password.submitted.connect(_reg_confirm.focus)
	_reg_confirm.submitted.connect(_submit_register)
	for field in [_reg_username, _reg_email, _reg_password, _reg_confirm]:
		box.add_child(field)
	_register_button = _accent_button("Create account", _submit_register)
	box.add_child(_register_button)
	return box


func _tab_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	return box


func _accent_button(label: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.theme_type_variation = &"AccentButton"
	button.custom_minimum_size = Vector2(0, 44)
	button.pressed.connect(on_pressed)
	return button


func _submit_login() -> void:
	if _busy:
		return
	_clear_errors()
	var errors := ApiRules.validate_login_form(_login_field.get_text(), _password_field.get_text())
	if _apply_local_errors(errors):
		return
	login_submitted.emit(_login_field.get_text().strip_edges(), _password_field.get_text())


func _submit_register() -> void:
	if _busy:
		return
	_clear_errors()
	var errors := ApiRules.validate_register_form(
		_reg_username.get_text(), _reg_email.get_text(),
		_reg_password.get_text(), _reg_confirm.get_text()
	)
	if _apply_local_errors(errors):
		return
	register_submitted.emit(
		_reg_username.get_text().strip_edges(), _reg_email.get_text().strip_edges(),
		_reg_password.get_text(), _reg_confirm.get_text()
	)


## Shows client-side errors; returns true when there were any.
func _apply_local_errors(errors: Dictionary) -> bool:
	var by_field := _current_field_map()
	for field in errors:
		if by_field.has(field):
			(by_field[field] as FormField).set_error(errors[field])
	return not errors.is_empty()


func _current_field_map() -> Dictionary:
	if _tabs.current_tab == TAB_REGISTER:
		return {
			"username": _reg_username,
			"email": _reg_email,
			"password": _reg_password,
			"password_confirmation": _reg_confirm,
		}
	return {"login": _login_field, "password": _password_field}


func _all_fields() -> Array[FormField]:
	var fields: Array[FormField] = [
		_login_field, _password_field, _reg_username, _reg_email, _reg_password, _reg_confirm
	]
	return fields


func _clear_errors() -> void:
	for field in _all_fields():
		field.set_error("")
	set_status("")


func _on_tab_changed(_tab: int) -> void:
	_clear_errors()
	focus_first.call_deferred()
