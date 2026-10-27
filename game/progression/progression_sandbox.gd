extends Node2D
## Standalone sandbox for the progression layer (no world/ or combat/ code).
## Run progression_sandbox.tscn directly (F6). See HELP for controls.

const SandboxActor := preload("res://progression/sandbox/sandbox_actor.gd")
const ARENA := Rect2(-640, -420, 1280, 840)
const HELP := (
	"PROGRESSION SANDBOX\n"
	+ "Left click: move / select enemy (pet attacks it) / pick up loot\n"
	+ "K: kill target (or nearest enemy)   H: nearest enemy hits you (pet defends)\n"
	+ "X: +100 XP   M: boss loot at mouse   P: kill pet   I: inventory"
)
const DUMMIES := [
	{"id": "slime", "name": "Slime", "xp": 15, "loot": "slime_drops", "level": 1,
		"color": Color(0.4, 0.85, 0.5), "pos": Vector2(220, -60)},
	{"id": "slime", "name": "Slime", "xp": 15, "loot": "slime_drops", "level": 1,
		"color": Color(0.4, 0.85, 0.5), "pos": Vector2(260, 90)},
	{"id": "wolf", "name": "Wolf", "xp": 30, "loot": "wolf_drops", "level": 3,
		"color": Color(0.6, 0.6, 0.65), "pos": Vector2(-240, 120)},
	{"id": "bandit", "name": "Bandit", "xp": 50, "loot": "bandit_drops", "level": 5,
		"color": Color(0.8, 0.45, 0.3), "pos": Vector2(-200, -180)},
	{"id": "boss", "name": "Star Ogre", "xp": 300, "loot": "boss_drops", "level": 8,
		"color": Color(0.7, 0.3, 0.8), "pos": Vector2(420, -260)},
]

var entities: Node2D
var player: Actor
var progression: Progression


func _ready() -> void:
	if Session.character.is_empty():
		Session.start_offline("Sandbox", "aries")
	get_viewport().physics_object_picking = true
	_build_navigation()
	entities = Node2D.new()
	entities.name = "Entities"
	entities.y_sort_enabled = true
	add_child(entities)
	player = _make_actor("Wanderer", Actor.Team.PLAYER, Color(0.4, 0.6, 1.0), 1)
	player.add_to_group("player")
	player.position = Vector2.ZERO
	entities.add_child(player)
	player.add_child(Camera2D.new())
	for spec in DUMMIES:
		_spawn_dummy(spec)
	progression = Progression.new()
	progression.name = "Progression"
	add_child(progression)
	progression.setup(player, entities)
	_build_help()


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_handle_click()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_K:
			_kill_target()
		KEY_H:
			_enemy_hits_player()
		KEY_X:
			progression.award_xp(100)
		KEY_M:
			progression.drop_loot("boss_drops", get_global_mouse_position())
		KEY_P:
			if is_instance_valid(progression.pet) and not progression.pet.is_dead:
				progression.pet.take_damage(progression.pet.hp, null)


## Mimics Zone: leave clicks on "clickable" nodes (loot) to their Area2D.
func _handle_click() -> void:
	var mouse := get_global_mouse_position()
	var query := PhysicsPointQueryParameters2D.new()
	query.position = mouse
	query.collide_with_areas = true
	for hit in get_world_2d().direct_space_state.intersect_point(query):
		var collider: Node = hit["collider"]
		if collider.is_in_group("clickable") or collider.get_parent().is_in_group("clickable"):
			return
	var enemy := _nearest_enemy(mouse, 28.0)
	if enemy:
		player.set("current_target", enemy)
		Events.target_changed.emit(enemy)
	else:
		player.move_to(mouse)
	get_viewport().set_input_as_handled()


func _kill_target() -> void:
	var target: Actor = player.get("current_target")
	if not is_instance_valid(target) or target.is_dead:
		target = _nearest_enemy(player.global_position, INF)
	if target:
		target.take_damage(target.hp, player)


func _enemy_hits_player() -> void:
	var enemy := _nearest_enemy(player.global_position, INF)
	if enemy and not player.is_dead:
		player.take_damage(25, enemy)


func _nearest_enemy(from: Vector2, max_distance: float) -> Actor:
	var best: Actor = null
	var best_distance := max_distance
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Actor
		if enemy == null or enemy.is_dead:
			continue
		var d := enemy.global_position.distance_to(from)
		if d < best_distance:
			best = enemy
			best_distance = d
	return best


func _make_actor(actor_name: String, team: Actor.Team, color: Color, level: int) -> Actor:
	var actor: Actor = SandboxActor.new()
	actor.display_name = actor_name
	actor.team = team
	actor.stats = Stats.new()
	actor.stats.level = level
	actor.set("body_color", color)
	actor.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	return actor


func _spawn_dummy(spec: Dictionary) -> void:
	var dummy := _make_actor(spec["name"], Actor.Team.ENEMY, spec["color"], spec["level"])
	dummy.set("enemy_id", spec["id"])
	dummy.set("xp", spec["xp"])
	dummy.set("loot_table", spec["loot"])
	dummy.position = spec["pos"]
	dummy.add_to_group("enemies")
	dummy.died.connect(_on_dummy_died.bind(dummy, spec))
	entities.add_child(dummy)


func _on_dummy_died(_killer: Node, dummy: Actor, spec: Dictionary) -> void:
	get_tree().create_timer(0.6).timeout.connect(dummy.queue_free)
	get_tree().create_timer(5.0).timeout.connect(_spawn_dummy.bind(spec))


func _build_navigation() -> void:
	var nav_poly := NavigationPolygon.new()
	nav_poly.vertices = PackedVector2Array([
		ARENA.position,
		Vector2(ARENA.end.x, ARENA.position.y),
		ARENA.end,
		Vector2(ARENA.position.x, ARENA.end.y),
	])
	nav_poly.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	var region := NavigationRegion2D.new()
	region.navigation_polygon = nav_poly
	add_child(region)


func _build_help() -> void:
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = HELP
	label.position = Vector2(12, 8)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	add_child(layer)


func _draw() -> void:
	draw_rect(ARENA, Color(0.16, 0.22, 0.16))
	var step := 64.0
	var x := ARENA.position.x
	while x <= ARENA.end.x:
		draw_line(Vector2(x, ARENA.position.y), Vector2(x, ARENA.end.y), Color(1, 1, 1, 0.05))
		x += step
	var y := ARENA.position.y
	while y <= ARENA.end.y:
		draw_line(Vector2(ARENA.position.x, y), Vector2(ARENA.end.x, y), Color(1, 1, 1, 0.05))
		y += step
	draw_rect(ARENA, Color(0.5, 0.6, 0.4), false, 3.0)
