extends Control
## Login flow root (res://ui/login/login.tscn, routed to by scenes/boot.gd).
## Screens: auth (login/register/offline) -> character select -> character
## create. Owns the ApiClient, fills Session and starts the game scene.
## The UI is built in code with a shared Theme (login_theme.gd).

const LoginTheme := preload("res://ui/login/login_theme.gd")
const LoginBackground := preload("res://ui/login/login_background.gd")
const AuthPanel := preload("res://ui/login/auth_panel.gd")
const CharacterSelectPanel := preload("res://ui/login/character_select_panel.gd")
const CharacterCreatePanel := preload("res://ui/login/character_create_panel.gd")

const GAME_SCENE := "res://scenes/game.tscn"
const SETTINGS_PATH := "user://login.cfg"
const SETTINGS_SECTION := "login"
const PANEL_WIDTH_NARROW := 440.0
const PANEL_WIDTH_WIDE := 560.0

var _api: ApiClient
var _card: PanelContainer
var _auth: AuthPanel
var _select: CharacterSelectPanel
var _create: CharacterCreatePanel
var _server_label: Label
var _characters: Array[Dictionary] = []


func _ready() -> void:
	theme = LoginTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_api = ApiClient.new()
	_api.name = "ApiClient"
	add_child(_api)  # applies ?api= / --api= overrides in its _ready
	_api.unauthorized.connect(_on_unauthorized)

	_build_ui()
	_server_label.text = "Server: %s" % Session.api_base_url
	_auth.set_last_username(_load_last_username())

	if Session.offline:
		Session.clear()
	if Session.token != "":
		_open_character_select()
	else:
		_show_screen(_auth)


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

	_auth = AuthPanel.new()
	_auth.login_submitted.connect(_on_login_submitted)
	_auth.register_submitted.connect(_on_register_submitted)
	_auth.offline_requested.connect(_on_offline_requested)
	_card.add_child(_auth)

	_select = CharacterSelectPanel.new()
	_select.play_requested.connect(_on_play_requested)
	_select.delete_requested.connect(_on_delete_requested)
	_select.create_requested.connect(_on_create_requested)
	_select.logout_requested.connect(_on_logout_requested)
	_card.add_child(_select)

	_create = CharacterCreatePanel.new()
	_create.set_signs(GameData.get_table("zodiac_signs"))
	_create.create_submitted.connect(_on_create_submitted)
	_create.back_requested.connect(_show_screen.bind(_select))
	_card.add_child(_create)

	_server_label = Label.new()
	_server_label.theme_type_variation = &"MutedLabel"
	_server_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_server_label.modulate = Color(1, 1, 1, 0.6)
	column.add_child(_server_label)


func _show_screen(screen: Control) -> void:
	for child in _card.get_children():
		(child as Control).visible = child == screen
	var width := 0.0  # the create screen sizes itself from its sign grid
	if screen == _auth:
		width = PANEL_WIDTH_NARROW
	elif screen == _select:
		width = PANEL_WIDTH_WIDE
	_card.custom_minimum_size = Vector2(width, 0)
	if screen == _auth:
		_auth.focus_first.call_deferred()
	elif screen == _create:
		_create.focus_first.call_deferred()


# --- Auth -------------------------------------------------------------------


func _on_login_submitted(login_name: String, password: String) -> void:
	_auth.set_busy(true, "Logging in...")
	var result := await _api.login(login_name, password)
	_finish_auth(result, login_name)


func _on_register_submitted(
	username: String, email: String, password: String, confirmation: String
) -> void:
	_auth.set_busy(true, "Creating your account...")
	var result := await _api.register(username, email, password, confirmation)
	_finish_auth(result, username)


func _finish_auth(result: ApiResult, typed_name: String) -> void:
	_auth.set_busy(false)
	if not result.ok:
		_auth.show_result(result)
		return
	_auth.set_status("")
	_auth.clear_password_fields()
	var username := str(Session.account.get("username", typed_name))
	_save_last_username(username)
	_auth.set_last_username(username)
	_open_character_select()


func _on_offline_requested() -> void:
	Session.clear()
	Session.start_offline()
	_start_game()


func _on_logout_requested() -> void:
	_select.set_busy(true, "Logging out...")
	await _api.logout()  # Session is cleared even if the server is unreachable.
	_select.set_busy(false)
	_select.set_status("")
	_auth.set_status("")
	_show_screen(_auth)


func _on_unauthorized() -> void:
	_auth.set_busy(false)
	_select.set_busy(false)
	_create.set_busy(false)
	_show_screen(_auth)
	_auth.set_status(ApiCodec.MSG_UNAUTHORIZED)


# --- Characters ---------------------------------------------------------------


func _open_character_select() -> void:
	_select.set_account_name(str(Session.account.get("username", "")))
	var none: Array[Dictionary] = []
	_select.set_characters(none, {})
	_show_screen(_select)
	await _refresh_characters()


func _refresh_characters() -> void:
	_select.set_busy(true, "Loading characters...")
	var result := await _api.list_characters()
	_select.set_busy(false)
	if not result.ok:
		if not result.is_unauthorized():
			_select.set_status(result.error_message)
		return
	_select.set_status("")
	_characters.clear()
	for raw in ApiCodec.extract_list(result.data, "characters"):
		_characters.append(ApiCodec.normalize_character(raw))
	_select.set_characters(_characters, GameData.get_table("zodiac_signs"))


func _on_play_requested(character: Dictionary) -> void:
	Session.offline = false
	Session.character = ApiCodec.normalize_character(character)
	_start_game()


func _on_delete_requested(character: Dictionary) -> void:
	_select.set_busy(true, "Deleting %s..." % str(character.get("name", "")))
	var result := await _api.delete_character(int(character.get("id", 0)))
	_select.set_busy(false)
	if not result.ok:
		if not result.is_unauthorized():
			_select.set_status(result.error_message)
		return
	await _refresh_characters()


func _on_create_requested() -> void:
	_create.reset()
	_show_screen(_create)


func _on_create_submitted(character_name: String, birth_sign: String) -> void:
	_create.set_busy(true, "Creating %s..." % character_name)
	var result := await _api.create_character(character_name, birth_sign)
	_create.set_busy(false)
	if not result.ok:
		if not result.is_unauthorized():
			_create.show_result(result)
		return
	_create.set_status("")
	_show_screen(_select)
	await _refresh_characters()


# --- Helpers ------------------------------------------------------------------


func _start_game() -> void:
	if not ResourceLoader.exists(GAME_SCENE):
		var message := "The game scene is not available yet (%s)." % GAME_SCENE
		push_error("Login: " + message)
		if _select.visible:
			_select.set_status(message)
		else:
			_auth.set_status(message)
		return
	get_tree().change_scene_to_file(GAME_SCENE)


func _load_last_username() -> String:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return ""
	return str(config.get_value(SETTINGS_SECTION, "last_username", ""))


func _save_last_username(username: String) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)  # keep other keys if the file exists
	config.set_value(SETTINGS_SECTION, "last_username", username)
	var err := config.save(SETTINGS_PATH)
	if err != OK:
		push_warning("Login: cannot save %s (error %d)" % [SETTINGS_PATH, err])
