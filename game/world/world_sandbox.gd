extends Node2D
## Standalone test scene for the world layer: loads the zone, spawns a
## placeholder Actor at the player spawn, follows it with the camera and moves
## it on Events.ground_clicked. Run world/world_sandbox.tscn directly (F6).

const ZONE_SCENE := preload("res://world/zone.tscn")
const BODY_RADIUS := 10.0

var zone: Zone
var actor: Actor
var camera: FollowCamera


func _ready() -> void:
	zone = ZONE_SCENE.instantiate()
	zone.show_spawn_debug = true
	add_child(zone)

	actor = _make_placeholder_actor()
	zone.get_entities_root().add_child(actor)
	actor.global_position = zone.get_player_spawn()

	camera = FollowCamera.new()
	add_child(camera)
	camera.set_bounds(zone.get_map_rect())
	camera.follow(actor)

	Events.ground_clicked.connect(_on_ground_clicked)


func _on_ground_clicked(world_pos: Vector2) -> void:
	actor.move_to(world_pos)


func _make_placeholder_actor() -> Actor:
	var a := Actor.new()
	a.name = "SandboxPlayer"
	a.display_name = "Sandbox"
	a.team = Actor.Team.PLAYER
	a.collision_layer = 2
	a.collision_mask = 1
	a.add_to_group("player")

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = BODY_RADIUS
	shape.shape = circle
	a.add_child(shape)

	var nav := NavigationAgent2D.new()
	nav.name = "NavAgent"
	nav.radius = BODY_RADIUS
	nav.path_desired_distance = 6.0
	nav.target_desired_distance = 6.0
	a.add_child(nav)

	# A blue disc standing on the actor's origin (its feet).
	var body := Polygon2D.new()
	body.color = Color(0.25, 0.55, 0.95)
	var points := PackedVector2Array()
	for i in 20:
		var angle := TAU * i / 20.0
		points.append(Vector2(cos(angle), sin(angle)) * BODY_RADIUS + Vector2(0, -BODY_RADIUS))
	body.polygon = points
	a.add_child(body)
	return a
