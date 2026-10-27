class_name Zone
extends Node2D
## An isometric field zone (contract: docs/ARCHITECTURE.md, "World").
## Everything is built in code from a seeded MapLayout:
##   Zone
##   ├─ Ground       TileMapLayer, placeholder art, collision on blocked tiles
##   ├─ Navigation   NavigationRegion2D, baked synchronously at load
##   ├─ GroundFx     click markers (drawn under actors)
##   ├─ Entities     y-sorted root for every Actor (get_entities_root())
##   └─ SpawnMarkers Marker2Ds in groups "player_spawn" / "enemy_spawns"
##
## Input: a left click (action "move_click") that reaches _unhandled_input
## emits Events.ground_clicked(world_pos), snapped to the closest navigable
## point. Clicks are ignored when a physics object in group "enemies" or
## "clickable" (or a child of one) is under the cursor, so those objects
## receive the click through physics picking (CollisionObject2D.input_event).

const TileArt := preload("res://world/tile_art.gd")
const ClickMarker := preload("res://world/click_marker.gd")

## Groups whose physics objects take clicks instead of the ground.
const CLICK_BLOCKER_GROUPS: Array[StringName] = [&"enemies", &"clickable"]

@export var zone_id: String = "field_01"
@export var map_seed: int = 1337
## Navigation keeps this far (pixels) from water and rocks.
@export var nav_agent_radius: float = 10.0
## Draw spawn camp rings and labels (for the sandbox / debugging).
@export var show_spawn_debug: bool = false

var layout: MapLayout

var _built: bool = false
var _ground: TileMapLayer
var _nav_region: NavigationRegion2D
var _ground_fx: Node2D
var _entities: Node2D
var _markers: Node2D
var _player_spawn: Marker2D


func _ready() -> void:
	_ensure_built()
	Events.zone_loaded.emit(zone_id)


# --- Contract API ----------------------------------------------------------


## Y-sorted parent for players, enemies, pets and loot.
func get_entities_root() -> Node2D:
	_ensure_built()
	return _entities


## World position where the local player appears.
func get_player_spawn() -> Vector2:
	_ensure_built()
	return _player_spawn.global_position


## Navigation map the zone's walkable area is registered on (the world's
## default 2D map, which NavigationAgent2D uses by default).
func get_navigation_map() -> RID:
	return get_world_2d().navigation_map


## True when world_pos is on a walkable tile inside the map.
func is_walkable(world_pos: Vector2) -> bool:
	_ensure_built()
	return layout.is_walkable_cell(world_to_cell(world_pos))


# --- Extra helpers ---------------------------------------------------------


## Closest point on the navigation mesh. Returns world_pos unchanged before
## the navigation map has synced (first physics frame).
func get_closest_navigable_point(world_pos: Vector2) -> Vector2:
	var map := get_navigation_map()
	if NavigationServer2D.map_get_iteration_id(map) == 0:
		return world_pos
	return NavigationServer2D.map_get_closest_point(map, world_pos)


## Bounding box of the map in world pixels (use for camera limits).
func get_map_rect() -> Rect2:
	_ensure_built()
	var outline := _map_outline()
	var rect := Rect2(to_global(outline[0]), Vector2.ZERO)
	for point in outline:
		rect = rect.expand(to_global(point))
	return rect


func world_to_cell(world_pos: Vector2) -> Vector2i:
	_ensure_built()
	return _ground.local_to_map(_ground.to_local(world_pos))


## World position of a cell's centre.
func cell_to_world(cell: Vector2i) -> Vector2:
	_ensure_built()
	return to_global(_cell_center(cell))


# --- Input -----------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("move_click"):
		return
	var world_pos := get_global_mouse_position()
	if _click_hits_blocker(world_pos):
		# Leave the event unhandled so physics picking reaches the enemy.
		return
	get_viewport().set_input_as_handled()
	var destination := get_closest_navigable_point(world_pos)
	_show_click_marker(destination)
	Events.ground_clicked.emit(destination)


func _click_hits_blocker(world_pos: Vector2) -> bool:
	var params := PhysicsPointQueryParameters2D.new()
	params.position = world_pos
	params.collide_with_areas = true
	params.collide_with_bodies = true
	var hits: Array = get_world_2d().direct_space_state.intersect_point(params, 16)
	for hit in hits:
		var node := (hit as Dictionary).get("collider") as Node
		while node != null and node != self:
			for group in CLICK_BLOCKER_GROUPS:
				if node.is_in_group(group):
					return true
			node = node.get_parent()
	return false


func _show_click_marker(world_pos: Vector2) -> void:
	for old in _ground_fx.get_children():
		old.queue_free()
	var marker := ClickMarker.new()
	_ground_fx.add_child(marker)
	marker.global_position = world_pos


# --- Building --------------------------------------------------------------


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	layout = MapLayout.generate(rng)
	_build_ground()
	_build_navigation()
	_ground_fx = _add_layer("GroundFx")
	_entities = _add_layer("Entities")
	_entities.y_sort_enabled = true
	_build_markers()


func _add_layer(layer_name: String) -> Node2D:
	var layer := Node2D.new()
	layer.name = layer_name
	add_child(layer)
	return layer


func _build_ground() -> void:
	_ground = TileMapLayer.new()
	_ground.name = "Ground"
	_ground.tile_set = TileArt.build_tile_set(MapLayout.TILE_SIZE)
	# Place cell (0, 0) on the zone origin so world positions match MapLayout.
	_ground.position = -_ground.map_to_local(Vector2i.ZERO)
	for y in layout.size.y:
		for x in layout.size.x:
			var cell := Vector2i(x, y)
			var atlas := TileArt.atlas_coords(layout.get_tile(cell))
			_ground.set_cell(cell, TileArt.SOURCE_ID, atlas)
	add_child(_ground)
	var probe := Vector2i(3, 1)
	if not _cell_center(probe).is_equal_approx(MapLayout.cell_to_world(probe)):
		push_warning("Zone: TileMapLayer layout differs from MapLayout iso math.")


## Bakes a NavigationPolygon from the map outline minus every blocked tile.
## Baking is synchronous (no threads), so it also works in web exports.
func _build_navigation() -> void:
	var source := NavigationMeshSourceGeometryData2D.new()
	source.add_traversable_outline(_map_outline())
	for y in layout.size.y:
		for x in layout.size.x:
			var cell := Vector2i(x, y)
			if not layout.is_walkable_cell(cell):
				source.add_obstruction_outline(_cell_outline(cell))

	var nav_poly := NavigationPolygon.new()
	nav_poly.agent_radius = nav_agent_radius
	NavigationServer2D.bake_from_source_geometry_data(nav_poly, source)
	if nav_poly.get_polygon_count() == 0:
		push_warning("Zone: navigation bake produced no polygons; using per-tile polygons.")
		_fill_tile_polygons(nav_poly)

	_nav_region = NavigationRegion2D.new()
	_nav_region.name = "Navigation"
	_nav_region.navigation_polygon = nav_poly
	add_child(_nav_region)


## Fallback: one polygon per walkable tile, sharing vertices with neighbours
## so the regions connect. No agent radius margin.
func _fill_tile_polygons(nav_poly: NavigationPolygon) -> void:
	var vertices := PackedVector2Array()
	var index_of := {}
	var polygons: Array[PackedInt32Array] = []
	for y in layout.size.y:
		for x in layout.size.x:
			var cell := Vector2i(x, y)
			if not layout.is_walkable_cell(cell):
				continue
			var polygon := PackedInt32Array()
			for point in _cell_outline(cell):
				var key := Vector2i(point.round())
				if not index_of.has(key):
					index_of[key] = vertices.size()
					vertices.append(Vector2(key))
				polygon.append(index_of[key])
			polygons.append(polygon)
	nav_poly.clear_polygons()
	nav_poly.vertices = vertices
	for polygon in polygons:
		nav_poly.add_polygon(polygon)


func _build_markers() -> void:
	_markers = _add_layer("SpawnMarkers")
	_player_spawn = Marker2D.new()
	_player_spawn.name = "PlayerSpawn"
	_player_spawn.position = _cell_center(layout.player_spawn_cell)
	_player_spawn.add_to_group("player_spawn")
	_markers.add_child(_player_spawn)

	for spawn in layout.enemy_spawns:
		var marker := Marker2D.new()
		var enemy_id: String = spawn["enemy_id"]
		marker.name = "%sSpawn" % enemy_id.capitalize().replace(" ", "")
		marker.position = _cell_center(spawn["cell"])
		marker.set_meta("enemy_id", enemy_id)
		marker.set_meta("count", int(spawn["count"]))
		marker.set_meta("radius", float(spawn["radius"]))
		marker.add_to_group("enemy_spawns")
		_markers.add_child(marker)
		if show_spawn_debug:
			_add_spawn_debug(marker, enemy_id, float(spawn["radius"]))


func _add_spawn_debug(marker: Marker2D, label_text: String, radius: float) -> void:
	var ring := Line2D.new()
	ring.width = 2.0
	ring.default_color = Color(1.0, 0.3, 0.3, 0.6)
	for i in 33:
		var angle := TAU * i / 32.0
		ring.add_point(Vector2(cos(angle) * radius, sin(angle) * radius * 0.5))
	marker.add_child(ring)
	var label := Label.new()
	label.text = label_text
	label.position = Vector2(-20, -radius * 0.5 - 24)
	marker.add_child(label)


# --- Geometry (zone-local coordinates) ------------------------------------


func _cell_center(cell: Vector2i) -> Vector2:
	return _ground.position + _ground.map_to_local(cell)


func _cell_outline(cell: Vector2i) -> PackedVector2Array:
	var center := _cell_center(cell)
	var outline := TileArt.diamond(MapLayout.TILE_SIZE)
	for i in outline.size():
		outline[i] += center
	return outline


## Outline of the whole map: the convex hull of the four corner tiles.
func _map_outline() -> PackedVector2Array:
	var last := layout.size - Vector2i.ONE
	var points := PackedVector2Array()
	for corner in [Vector2i(0, 0), Vector2i(last.x, 0), last, Vector2i(0, last.y)]:
		points.append_array(_cell_outline(corner))
	var hull := Geometry2D.convex_hull(points)
	# convex_hull() repeats the first point at the end; outlines must not.
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)
	return hull
