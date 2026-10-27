extends TestCase


func _layout(seed_value: int = 1337) -> MapLayout:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return MapLayout.generate(rng)


func test_size_is_forty_by_forty() -> void:
	var layout := _layout()
	assert_eq(layout.size, Vector2i(40, 40), "size")
	assert_eq(layout.tiles.size(), 1600, "tile count")


func test_same_seed_same_map() -> void:
	assert_eq(_layout(42).tiles, _layout(42).tiles, "tiles")


func test_different_seed_different_map() -> void:
	assert_true(_layout(1).tiles != _layout(2).tiles, "seeds 1 and 2 should differ")


func test_has_blocked_and_walkable_tiles() -> void:
	var layout := _layout()
	var walkable := layout.walkable_count()
	var blocked := layout.tiles.size() - walkable
	assert_true(blocked >= 40, "expected some water/rock, got %d" % blocked)
	assert_true(walkable >= 1200, "expected mostly walkable ground, got %d" % walkable)


func test_out_of_bounds_is_blocked() -> void:
	var layout := _layout()
	assert_true(not layout.is_walkable_cell(Vector2i(-1, 0)), "x < 0")
	assert_true(not layout.is_walkable_cell(Vector2i(0, 40)), "y >= size")
	assert_eq(layout.get_tile(Vector2i(99, 99)), MapLayout.Tile.ROCK, "oob tile")


func test_every_walkable_cell_is_reachable_from_spawn() -> void:
	for seed_value in [1, 7, 1337, 90210]:
		var layout := _layout(seed_value)
		var reachable := layout.reachable_from(layout.player_spawn_cell)
		assert_eq(reachable.size(), layout.walkable_count(), "seed %d reachable" % seed_value)


func test_player_spawn_is_on_town_edge() -> void:
	var layout := _layout()
	var cell := layout.player_spawn_cell
	assert_true(layout.is_walkable_cell(cell), "spawn walkable")
	assert_true(MapLayout.TOWN_RECT.grow(1).has_point(cell), "spawn next to town")


func test_enemy_spawns_match_contract() -> void:
	var layout := _layout()
	var ids: Array = []
	for spawn in layout.enemy_spawns:
		ids.append(spawn["enemy_id"])
		var count: int = spawn["count"]
		var radius: float = spawn["radius"]
		assert_true(count >= 3 and count <= 5, "count in 3..5")
		assert_near(radius, 120.0, 30.0, "radius")
	assert_eq(ids, ["slime", "wolf", "bandit"], "enemy ids")


func test_spawn_areas_are_clear_and_separated() -> void:
	var layout := _layout()
	var centers: Array[Vector2i] = [layout.player_spawn_cell]
	for spawn in layout.enemy_spawns:
		var cell: Vector2i = spawn["cell"]
		centers.append(cell)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var near := cell + Vector2i(dx, dy)
				assert_true(layout.is_walkable_cell(near), "%s blocked near %s" % [near, cell])
	for i in centers.size():
		for j in range(i + 1, centers.size()):
			var d := Vector2(centers[i]).distance_to(Vector2(centers[j]))
			assert_true(d >= 8.0, "spawns %s and %s too close" % [centers[i], centers[j]])
