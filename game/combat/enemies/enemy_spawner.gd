class_name EnemySpawner
extends Node
## Spawns enemies at every Marker2D in group "enemy_spawns" and respawns each
## one `respawn_delay` seconds after it dies.
## Marker metas: enemy_id (String, key in data/enemies.json), count (int),
## radius (float, enemies are scattered within it).

signal enemy_spawned(enemy: Enemy)

const ENEMY_SCENE := preload("res://combat/enemies/enemy.tscn")
const ENEMY_TABLE := "enemies"

@export var respawn_delay: float = 10.0

var _entities_root: Node2D
var _rng := RandomNumberGenerator.new()


## Spawns the initial enemies as children of `entities_root`.
func setup(entities_root: Node2D) -> void:
	_entities_root = entities_root
	_rng.randomize()
	for node in entities_root.get_tree().get_nodes_in_group("enemy_spawns"):
		var marker := node as Node2D
		if marker == null:
			continue
		var count := int(marker.get_meta("count", 1))
		for i in count:
			_spawn_at_marker(marker)


## Spawns one enemy of `enemy_id` at `world_pos`. Returns null for unknown ids.
func spawn_enemy(enemy_id: String, world_pos: Vector2) -> Enemy:
	if _entities_root == null:
		push_warning("EnemySpawner: call setup() before spawn_enemy()")
		return null
	var data := GameData.get_entry(ENEMY_TABLE, enemy_id)
	if data.is_empty():
		push_warning("EnemySpawner: unknown enemy id '%s'" % enemy_id)
		return null
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.configure(enemy_id, data)
	enemy.position = _entities_root.to_local(world_pos)
	_entities_root.add_child(enemy)
	enemy_spawned.emit(enemy)
	return enemy


## Living enemies spawned by this spawner (and any others in the group).
func get_live_enemies() -> Array[Enemy]:
	var result: Array[Enemy] = []
	if _entities_root == null:
		return result
	for node in _entities_root.get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy and not enemy.is_dead:
			result.append(enemy)
	return result


func _spawn_at_marker(marker: Node2D) -> void:
	var enemy_id := str(marker.get_meta("enemy_id", ""))
	var radius := float(marker.get_meta("radius", 64.0))
	var offset := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, radius)
	var spawn_pos := _snap_to_navigable(marker, marker.global_position + offset)
	var enemy := spawn_enemy(enemy_id, spawn_pos)
	if enemy:
		# Weak reference: the zone (and its markers) may be unloaded meanwhile.
		enemy.died.connect(_on_enemy_died.bind(weakref(marker)))


func _on_enemy_died(_killer: Node, marker_ref: WeakRef) -> void:
	if not is_instance_valid(_entities_root) or not _entities_root.is_inside_tree():
		return
	_entities_root.get_tree().create_timer(respawn_delay).timeout.connect(
		_respawn.bind(marker_ref)
	)


func _respawn(marker_ref: WeakRef) -> void:
	var marker := marker_ref.get_ref() as Node2D
	if marker == null or not marker.is_inside_tree():
		return
	if not is_instance_valid(_entities_root) or not _entities_root.is_inside_tree():
		return
	_spawn_at_marker(marker)


## Random camp points can land on blocked tiles. If an ancestor of the marker
## offers get_closest_navigable_point(pos) (the world's Zone does), snap to it;
## otherwise (e.g. the combat sandbox) keep the point as is.
func _snap_to_navigable(marker: Node, world_pos: Vector2) -> Vector2:
	var node := marker.get_parent()
	while node != null:
		if node.has_method("get_closest_navigable_point"):
			var nav_point: Variant = node.call("get_closest_navigable_point", world_pos)
			if nav_point is Vector2:
				return nav_point as Vector2
			return world_pos
		node = node.get_parent()
	return world_pos
