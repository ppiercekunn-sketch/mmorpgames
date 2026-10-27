extends Node2D
## Stand-alone combat test scene: flat ground, no navigation map, no world code.
## Emits Events.ground_clicked on left click itself, spawns the player, a few
## camps of every enemy type through an EnemySpawner, and the combat HUD.
## Debug keys: "=" / "-" raise / lower the player level (to try every skill).

const PLAYER_SCENE := preload("res://combat/player/player.tscn")
const HUD_SCENE := preload("res://combat/ui/combat_hud.tscn")
const GROUND_HALF_SIZE := Vector2(1400, 1000)
const GRID_STEP := 64.0
## [enemy_id, position, count, radius]
const CAMPS: Array = [
	["slime", Vector2(-360, -180), 4, 90.0],
	["slime", Vector2(-250, 260), 3, 70.0],
	["wolf", Vector2(420, -240), 3, 90.0],
	["bandit", Vector2(80, 420), 2, 60.0],
	["field_boss", Vector2(950, 380), 1, 0.0],
]

var player: Player
var spawner: EnemySpawner


func _ready() -> void:
	if Session.character.is_empty():
		Session.start_offline("Sandbox Warrior", "aries")
	var entities := Node2D.new()
	entities.name = "Entities"
	entities.y_sort_enabled = true
	add_child(entities)

	for camp: Array in CAMPS:
		var marker := Marker2D.new()
		marker.position = camp[1]
		marker.set_meta("enemy_id", camp[0])
		marker.set_meta("count", camp[2])
		marker.set_meta("radius", camp[3])
		marker.add_to_group("enemy_spawns")
		add_child(marker)

	player = PLAYER_SCENE.instantiate() as Player
	player.use_navigation = false
	player.position = Vector2.ZERO
	entities.add_child(player)
	var camera := Camera2D.new()
	camera.position_smoothing_enabled = true
	player.add_child(camera)
	camera.make_current()
	Events.player_spawned.emit(player)

	spawner = EnemySpawner.new()
	spawner.name = "EnemySpawner"
	add_child(spawner)
	spawner.setup(entities)

	add_child(HUD_SCENE.instantiate())
	_add_help_text()


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		Events.ground_clicked.emit(get_global_mouse_position())
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		if key.keycode == KEY_EQUAL or key.keycode == KEY_KP_ADD:
			_change_level(1)
		elif key.keycode == KEY_MINUS or key.keycode == KEY_KP_SUBTRACT:
			_change_level(-1)


func _change_level(delta_levels: int) -> void:
	var new_level := clampi(player.stats.level + delta_levels, 1, 10)
	if new_level == player.stats.level:
		return
	player.stats.level = new_level
	player.heal(player.stats.max_hp(), player)
	player.restore_mp(player.stats.max_mp())
	Events.level_up.emit(player, new_level)


func _add_help_text() -> void:
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = (
		"Combat sandbox - left click: move / target   1-6: skills   = / -: level up / down"
	)
	label.position = Vector2(12, 150)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	layer.add_child(label)
	add_child(layer)


func _draw() -> void:
	var rect := Rect2(-GROUND_HALF_SIZE, GROUND_HALF_SIZE * 2.0)
	draw_rect(rect, Color(0.28, 0.42, 0.24))
	var line_color := Color(0, 0, 0, 0.08)
	var x := rect.position.x
	while x <= rect.end.x:
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), line_color)
		x += GRID_STEP
	var y := rect.position.y
	while y <= rect.end.y:
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), line_color)
		y += GRID_STEP
