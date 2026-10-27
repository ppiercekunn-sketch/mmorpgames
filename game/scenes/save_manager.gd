extends Node
## Local save orchestration for the game scene (created by game.gd).
## Restores Session.pending_save after the scene is assembled and autosaves
## into Session.save_slot: every AUTOSAVE_SECONDS of play, on player level up,
## when the window is closed (NOTIFICATION_WM_CLOSE_REQUEST) and when quitting
## to the title (game.gd calls save_now()). Also saves, without a toast, when
## the app loses focus (best effort for web tabs, which get no close event).
## Shows a small "Saved" toast. Does nothing when there is no save slot
## (`-- --offline` games are unsaved). File format: core/save_game.gd.

signal saved(ok: bool)

const LoginTheme := preload("res://ui/login/login_theme.gd")

const AUTOSAVE_SECONDS := 60.0
const FOCUS_SAVE_MIN_INTERVAL_MSEC := 15000
const TOAST_HOLD := 1.2
const TOAST_FADE := 0.5

var zone: Zone
var player: Actor
var progression: Progression
## Seconds played in this save (counts only while the tree is not paused).
var playtime: float = 0.0

var _active: bool = false
var _last_save_msec: int = -FOCUS_SAVE_MIN_INTERVAL_MSEC
var _timer: Timer
var _toast_layer: CanvasLayer
var _toast: PanelContainer
var _toast_label: Label
var _toast_tween: Tween


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = AUTOSAVE_SECONDS
	_timer.timeout.connect(_on_autosave_timer)
	add_child(_timer)
	_build_toast()


func _process(delta: float) -> void:
	if _active:
		playtime += delta


## Where the player should appear: the saved position when it is in this zone
## and walkable, else the zone's spawn point.
static func start_position(p_zone: Zone, data: Dictionary) -> Vector2:
	var spawn := p_zone.get_player_spawn()
	var saved_pos: Variant = SaveGame.get_position(data)
	if saved_pos == null or SaveGame.get_zone_id(data) != p_zone.zone_id:
		return spawn
	var pos: Vector2 = saved_pos
	return pos if p_zone.is_walkable(pos) else spawn


## Call once the zone, player and Progression are set up. Applies `data`
## (a parsed save, or {} for a new character) and starts autosaving.
func setup(p_zone: Zone, p_player: Actor, p_progression: Progression, data: Dictionary) -> void:
	zone = p_zone
	player = p_player
	progression = p_progression
	if not data.is_empty():
		playtime = float(data.get("playtime", 0.0))
		progression.apply_save_data(data)
		_restore_vitals(data.get("vitals", {}))
	if is_instance_valid(progression.pet):
		progression.pet.teleport_to_owner()
	if not Events.level_up.is_connected(_on_level_up):
		Events.level_up.connect(_on_level_up)
	_active = true
	if can_save():
		_timer.start()
		# Claim the slot right away with the starting state (new games).
		save_now.call_deferred(false)


func can_save() -> bool:
	return (_active and Session.has_save_slot() and is_instance_valid(player)
		and is_instance_valid(progression))


## Writes the current game to Session.save_slot. Returns true on success.
func save_now(show_toast: bool = true) -> bool:
	if not can_save():
		return false
	var err := SaveGame.write_slot(Session.save_slot, build_save_data())
	var ok := err == OK
	_last_save_msec = Time.get_ticks_msec()
	if not ok:
		push_warning("SaveManager: saving slot %d failed (error %d)" % [Session.save_slot, err])
	if show_toast or not ok:
		_show_toast("Saved" if ok else "Save failed")
	saved.emit(ok)
	return ok


## The current game in the SaveGame format.
func build_save_data() -> Dictionary:
	var character: Dictionary = Session.character
	var data := SaveGame.new_save(
		str(character.get("name", "Wanderer")), str(character.get("birth_sign", "aries")))
	var progress := progression.get_save_data()
	for key in ["level", "xp", "gold"]:
		data["character"][key] = progress["character"][key]
	data["inventory"] = progress["inventory"]
	data["pet"] = progress["pet"]
	data["playtime"] = playtime
	data["saved_at"] = int(Time.get_unix_time_from_system())
	data["zone"]["id"] = zone.zone_id if is_instance_valid(zone) else ""
	if not player.is_dead:
		# A dead player is saved without a position / vitals: they load at spawn, full.
		var pos := player.global_position
		data["zone"]["position"] = {"x": pos.x, "y": pos.y}
		data["vitals"] = {"hp": player.hp, "mp": player.mp}
	return data


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			save_now(false)
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			if Time.get_ticks_msec() - _last_save_msec >= FOCUS_SAVE_MIN_INTERVAL_MSEC:
				save_now(false)


func _restore_vitals(vitals: Variant) -> void:
	if not vitals is Dictionary or not is_instance_valid(player) or player.is_dead:
		return
	var max_hp := player.stats.max_hp()
	var max_mp := player.stats.max_mp()
	var hp := int(vitals.get("hp", -1))
	var mp := int(vitals.get("mp", -1))
	# Set directly (not take_damage/heal) so no combat events fire on load.
	player.hp = max_hp if hp <= 0 else mini(hp, max_hp)
	player.mp = max_mp if mp < 0 else mini(mp, max_mp)
	player.hp_changed.emit(player.hp, max_hp)
	player.mp_changed.emit(player.mp, max_mp)


func _on_autosave_timer() -> void:
	save_now()


func _on_level_up(actor: Node, _new_level: int) -> void:
	if actor == player:
		# Deferred so Progression finishes updating XP/gold first.
		save_now.call_deferred(true)


# --- Toast ---------------------------------------------------------------------


func _build_toast() -> void:
	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = 40
	_toast_layer.process_mode = Node.PROCESS_MODE_ALWAYS  # visible in the pause menu
	add_child(_toast_layer)
	_toast = PanelContainer.new()
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_theme_stylebox_override(
		"panel", LoginTheme.box(Color(LoginTheme.NAVY_DARK, 0.85), LoginTheme.GOLD_DARK, 1, 6, 8))
	_toast.anchor_left = 1.0
	_toast.anchor_right = 1.0
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.offset_right = -16.0
	_toast.offset_bottom = -120.0
	_toast.modulate.a = 0.0
	_toast_layer.add_child(_toast)
	_toast_label = Label.new()
	_toast_label.add_theme_color_override("font_color", LoginTheme.GOLD)
	_toast_label.add_theme_font_size_override("font_size", 15)
	_toast.add_child(_toast_label)


func _show_toast(text: String) -> void:
	_toast_label.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = _toast.create_tween()
	_toast_tween.tween_interval(TOAST_HOLD)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, TOAST_FADE)
