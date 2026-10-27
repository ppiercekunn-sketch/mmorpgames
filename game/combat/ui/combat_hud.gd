class_name CombatHUD
extends CanvasLayer
## Combat HUD: player HP/MP bars, 6-slot skill hotbar (key, name, cooldown
## sweep, locked state), target frame, cast-failure messages and floating
## damage numbers. Finds the player through group "player" automatically;
## set_player() can be called to bind one explicitly. All nodes are built in
## code; only the hotbar slots catch the mouse (clicking one casts the skill).

const SLOT_SIZE := Vector2(64, 64)
const DAMAGE_COLOR := Color(1, 1, 1)
const CRIT_COLOR := Color(1, 0.85, 0.2)
const PLAYER_HIT_COLOR := Color(1, 0.3, 0.3)
const FLOAT_TIME := 0.9
const MESSAGE_TIME := 1.6

var _player: Player
var _root: Control
var _name_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _mp_bar: ProgressBar
var _mp_label: Label
var _buff_label: Label
var _target_panel: PanelContainer
var _target_name: Label
var _target_hp_bar: ProgressBar
var _target_hp_label: Label
var _message_label: Label
var _message_time: float = 0.0
## One dictionary per hotbar slot: {panel, name, key, cooldown, cooldown_text, lock, lock_text}
var _slot_views: Array[Dictionary] = []
var _target: Actor


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_player_frame()
	_build_target_frame()
	_build_hotbar()
	_build_message_label()
	Events.actor_damaged.connect(_on_actor_damaged)
	Events.target_changed.connect(_on_target_changed)
	Events.player_spawned.connect(_on_player_spawned)


## Binds the HUD to `player` (otherwise the first node in group "player" is used).
func set_player(player: Player) -> void:
	if _player == player:
		return
	_player = player
	if _player == null:
		return
	if not _player.cast_failed.is_connected(_on_cast_failed):
		_player.cast_failed.connect(_on_cast_failed)
	_refresh_hotbar_labels()


## Shows a short message above the hotbar.
func show_message(text: String) -> void:
	_message_label.text = text
	_message_time = MESSAGE_TIME
	_message_label.modulate.a = 1.0


func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		_player = null
		var found := get_tree().get_first_node_in_group("player") as Player
		if found:
			set_player(found)
	if _player:
		_update_player_frame()
		_update_hotbar()
	_update_target_frame()
	if _message_time > 0.0:
		_message_time -= delta
		_message_label.modulate.a = clampf(_message_time / 0.4, 0.0, 1.0)


# --- Player frame -----------------------------------------------------------------


func _build_player_frame() -> void:
	var panel := _make_panel()
	panel.position = Vector2(12, 12)
	_root.add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size = Vector2(240, 0)
	panel.add_child(box)
	_name_label = _make_label("", 15)
	box.add_child(_name_label)
	var hp := _make_bar(Color(0.8, 0.2, 0.2))
	_hp_bar = hp[0]
	_hp_label = hp[1]
	box.add_child(_hp_bar)
	var mp := _make_bar(Color(0.25, 0.45, 0.9))
	_mp_bar = mp[0]
	_mp_label = mp[1]
	box.add_child(_mp_bar)
	_buff_label = _make_label("", 12)
	_buff_label.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	box.add_child(_buff_label)


func _update_player_frame() -> void:
	_name_label.text = "Lv %d  %s" % [_player.stats.level, _player.display_name]
	if _player.is_dead:
		_name_label.text += "  (respawning...)"
	_set_bar(_hp_bar, _hp_label, _player.hp, _player.stats.max_hp())
	_set_bar(_mp_bar, _mp_label, _player.mp, _player.stats.max_mp())
	var parts: PackedStringArray = []
	var buffs := _player.get_active_buffs()
	for effect: Variant in buffs:
		var buff: Dictionary = buffs[effect]
		var label := "ATK UP" if effect == "buff_attack" else "GUARD"
		parts.append("%s %ds" % [label, ceili(float(buff.get("remaining", 0.0)))])
	_buff_label.text = "  ".join(parts)


# --- Target frame -----------------------------------------------------------------


func _build_target_frame() -> void:
	_target_panel = _make_panel()
	_target_panel.visible = false
	_root.add_child(_target_panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size = Vector2(260, 0)
	_target_panel.add_child(box)
	_target_name = _make_label("", 15)
	_target_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_target_name)
	var hp := _make_bar(Color(0.8, 0.2, 0.2))
	_target_hp_bar = hp[0]
	_target_hp_label = hp[1]
	box.add_child(_target_hp_bar)
	_target_panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 12
	)
	_target_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH


func _update_target_frame() -> void:
	var valid := is_instance_valid(_target) and not _target.is_dead
	_target_panel.visible = valid
	if not valid:
		return
	_target_name.text = "Lv %d  %s" % [_target.stats.level, _target.display_name]
	_set_bar(_target_hp_bar, _target_hp_label, _target.hp, _target.stats.max_hp())


func _on_target_changed(new_target: Node) -> void:
	_target = new_target as Actor


# --- Hotbar -------------------------------------------------------------------------


func _build_hotbar() -> void:
	var bar := HBoxContainer.new()
	bar.name = "Hotbar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("separation", 6)
	_root.add_child(bar)
	for i in Player.HOTBAR_SIZE:
		bar.add_child(_build_slot(i))
	bar.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 16
	)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _build_slot(index: int) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = SLOT_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _make_style(Color(0.12, 0.12, 0.16, 0.9)))
	panel.gui_input.connect(_on_slot_gui_input.bind(index))

	var skill_name := _make_label("", 11)
	skill_name.position = Vector2(0, 40)
	skill_name.size = Vector2(SLOT_SIZE.x, 20)
	skill_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skill_name.clip_text = true
	panel.add_child(skill_name)

	var cooldown := ColorRect.new()
	cooldown.color = Color(0, 0, 0, 0.65)
	cooldown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cooldown.size = Vector2(SLOT_SIZE.x, 0)
	panel.add_child(cooldown)

	var cooldown_text := _make_label("", 18)
	cooldown_text.position = Vector2(0, 10)
	cooldown_text.size = Vector2(SLOT_SIZE.x, 24)
	cooldown_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(cooldown_text)

	var lock := ColorRect.new()
	lock.color = Color(0.05, 0.05, 0.05, 0.75)
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock.size = SLOT_SIZE
	panel.add_child(lock)

	var lock_text := _make_label("", 12)
	lock_text.position = Vector2(0, 16)
	lock_text.size = Vector2(SLOT_SIZE.x, 20)
	lock_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_text.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	panel.add_child(lock_text)

	var key := _make_label(str(index + 1), 12)
	key.position = Vector2(4, 2)
	key.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	panel.add_child(key)

	_slot_views.append(
		{
			"panel": panel,
			"name": skill_name,
			"cooldown": cooldown,
			"cooldown_text": cooldown_text,
			"lock": lock,
			"lock_text": lock_text,
		}
	)
	return panel


func _refresh_hotbar_labels() -> void:
	var slots := _player.get_skill_slots()
	for i in _slot_views.size():
		var skill_id := slots[i] if i < slots.size() else ""
		var skill := _player.get_skill(skill_id)
		var view: Dictionary = _slot_views[i]
		(view["name"] as Label).text = str(skill.get("name", ""))
		(view["panel"] as Panel).tooltip_text = _tooltip_for(skill)


func _update_hotbar() -> void:
	var slots := _player.get_skill_slots()
	for i in _slot_views.size():
		var view: Dictionary = _slot_views[i]
		var skill_id := slots[i] if i < slots.size() else ""
		var skill := _player.get_skill(skill_id)
		var locked := skill.is_empty() or not _player.is_skill_unlocked(skill_id)
		(view["lock"] as ColorRect).visible = locked
		var lock_text := view["lock_text"] as Label
		lock_text.visible = locked and not skill.is_empty()
		lock_text.text = "Lv %d" % int(skill.get("unlock_level", 1))
		var frac := 0.0 if locked else _player.cooldowns.fraction(skill_id)
		(view["cooldown"] as ColorRect).size = Vector2(SLOT_SIZE.x, SLOT_SIZE.y * frac)
		var left := _player.cooldowns.remaining(skill_id)
		var cooldown_text := view["cooldown_text"] as Label
		cooldown_text.text = "%d" % ceili(left) if left > 0.0 and not locked else ""
		var name_label := view["name"] as Label
		var affordable := _player.mp >= int(skill.get("mp_cost", 0))
		name_label.modulate = Color.WHITE if affordable else Color(0.5, 0.6, 1.0)


func _on_slot_gui_input(event: InputEvent, index: int) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT and _player:
		_player.try_cast_slot(index)
		get_viewport().set_input_as_handled()


func _tooltip_for(skill: Dictionary) -> String:
	if skill.is_empty():
		return ""
	return "%s (Lv %d)\nMP %d  ·  Cooldown %ss\n%s" % [
		str(skill.get("name", "")),
		int(skill.get("unlock_level", 1)),
		int(skill.get("mp_cost", 0)),
		str(skill.get("cooldown", 0)),
		str(skill.get("description", "")),
	]


# --- Messages and floating numbers -------------------------------------------------


func _build_message_label() -> void:
	_message_label = _make_label("", 16)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
	_root.add_child(_message_label)
	# Full-width strip just above the hotbar.
	_message_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_message_label.offset_top = -SLOT_SIZE.y - 56
	_message_label.offset_bottom = -SLOT_SIZE.y - 28


func _on_cast_failed(_skill_id: String, reason: String) -> void:
	show_message(SkillRules.reason_text(reason))


func _on_player_spawned(player: Node) -> void:
	if player is Player:
		set_player(player as Player)


func _on_actor_damaged(target: Node, amount: int, _source: Node, is_crit: bool) -> void:
	var target_item := target as Node2D
	if target_item == null or not target_item.is_inside_tree():
		return
	var color := DAMAGE_COLOR
	if target_item.is_in_group("player"):
		color = PLAYER_HIT_COLOR
	elif is_crit:
		color = CRIT_COLOR
	var text := "%d!" % amount if is_crit else str(amount)
	var screen_pos := target_item.get_global_transform_with_canvas().origin
	_spawn_floating_text(text, screen_pos + Vector2(0, -50), color, 26 if is_crit else 18)


func _spawn_floating_text(text: String, screen_pos: Vector2, color: Color, font_size: int) -> void:
	var label := _make_label(text, font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(80, 30)
	var jitter := Vector2(randf_range(-12.0, 12.0), 0)
	label.position = screen_pos - Vector2(40, 15) + jitter
	_root.add_child(label)
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 40.0, FLOAT_TIME)
	tween.tween_property(label, "modulate:a", 0.0, FLOAT_TIME).set_delay(FLOAT_TIME * 0.4)
	tween.chain().tween_callback(label.queue_free)


# --- Widget helpers -------------------------------------------------------------------


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	return label


## Returns [ProgressBar, Label] with the label centred over the bar.
func _make_bar(fill_color: Color) -> Array:
	var bar := ProgressBar.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 18)
	bar.add_theme_stylebox_override("background", _make_style(Color(0.1, 0.1, 0.1, 0.85)))
	bar.add_theme_stylebox_override("fill", _make_style(fill_color))
	var label := _make_label("", 12)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return [bar, label]


func _set_bar(bar: ProgressBar, label: Label, current: int, maximum: int) -> void:
	bar.max_value = maxi(maximum, 1)
	bar.value = current
	label.text = "%d / %d" % [current, maximum]


func _make_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _make_style(Color(0.05, 0.06, 0.1, 0.75))
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _make_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(3)
	return style
