extends TestCase

const TILE := Vector2i(64, 32)


func test_cell_to_world_axes() -> void:
	assert_eq(MapLayout.cell_to_world(Vector2i(0, 0), TILE), Vector2(0, 0), "origin")
	assert_eq(MapLayout.cell_to_world(Vector2i(1, 0), TILE), Vector2(32, 16), "+x")
	assert_eq(MapLayout.cell_to_world(Vector2i(0, 1), TILE), Vector2(-32, 16), "+y")
	assert_eq(MapLayout.cell_to_world(Vector2i(2, 2), TILE), Vector2(0, 64), "diagonal")


func test_round_trip_every_cell() -> void:
	for y in 40:
		for x in 40:
			var cell := Vector2i(x, y)
			var back := MapLayout.world_to_cell(MapLayout.cell_to_world(cell, TILE), TILE)
			if back != cell:
				fail("round trip %s -> %s" % [cell, back])
				return


func test_points_inside_diamond_map_to_cell() -> void:
	var cell := Vector2i(5, 3)
	var center := MapLayout.cell_to_world(cell, TILE)
	# Just inside each corner of the diamond.
	for offset in [Vector2(0, -15), Vector2(31, 0), Vector2(0, 15), Vector2(-31, 0)]:
		assert_eq(MapLayout.world_to_cell(center + offset, TILE), cell, "offset %s" % offset)
	# Just past the right corner is the (x+1, y-1) neighbour.
	assert_eq(
		MapLayout.world_to_cell(center + Vector2(33, 0), TILE), Vector2i(6, 2), "past right corner"
	)


func test_cell_diamond_corners() -> void:
	var d := MapLayout.cell_diamond(Vector2i(1, 0), TILE)
	assert_eq(d.size(), 4, "corner count")
	assert_eq(d[0], Vector2(32, 0), "top")
	assert_eq(d[1], Vector2(64, 16), "right")
	assert_eq(d[2], Vector2(32, 32), "bottom")
	assert_eq(d[3], Vector2(0, 16), "left")


func test_world_rect_covers_map() -> void:
	var layout := MapLayout.new()
	var rect := layout.world_rect(TILE)
	# 40x40 diamond: 40 tiles wide and 40 half-tiles tall on each side.
	assert_eq(rect.size, Vector2(40 * 64, 40 * 32), "size")
	assert_eq(rect.position, Vector2(-40 * 32, -16), "position")
	for cell in [Vector2i(0, 0), Vector2i(39, 0), Vector2i(0, 39), Vector2i(39, 39)]:
		assert_true(rect.has_point(MapLayout.cell_to_world(cell, TILE)), "has %s" % cell)
