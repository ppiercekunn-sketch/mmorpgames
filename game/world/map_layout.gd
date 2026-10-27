class_name MapLayout
extends RefCounted
## Pure data for an isometric field zone: the tile grid, spawn points and the
## isometric coordinate math. No scene or autoload dependencies, so tests and
## the M2 headless server can use it directly.
##
## Cells are Vector2i(x, y). On screen x grows towards the lower right and y
## towards the lower left ("diamond down" layout); cell (0, 0) is centred on
## world (0, 0). Generation is deterministic for a given RNG seed.

enum Tile { GRASS, GRASS_ALT, DIRT, WATER, ROCK }

const DEFAULT_SIZE := Vector2i(40, 40)
## Pixel size of one isometric tile (full diamond width x height).
const TILE_SIZE := Vector2i(64, 32)
## The player appears on the east edge of the town.
const PLAYER_SPAWN_CELL := Vector2i(7, 20)
## Town square (dirt plaza) on the west side of the map.
const TOWN_RECT := Rect2i(1, 16, 7, 9)
## Cells within this Chebyshev distance of a spawn are kept free of obstacles.
const SPAWN_CLEAR_RADIUS := 4
## Enemy camps. "enemy_id" values are defined by combat (data/enemies.json).
const ENEMY_CAMPS := [
	{"enemy_id": "slime", "cell": Vector2i(12, 29), "count": 5, "radius": 120.0},
	{"enemy_id": "wolf", "cell": Vector2i(31, 13), "count": 4, "radius": 120.0},
	{"enemy_id": "bandit", "cell": Vector2i(33, 30), "count": 3, "radius": 120.0},
]
## Water blobs: centre cell and radii in cells.
const LAKES := [
	{"cell": Vector2i(15, 8), "radii": Vector2(5.0, 3.0)},
	{"cell": Vector2i(24, 32), "radii": Vector2(3.0, 3.0)},
	{"cell": Vector2i(34, 5), "radii": Vector2(3.0, 2.0)},
]
const ROCK_CLUSTERS := 16

var size: Vector2i = DEFAULT_SIZE
## Row-major tile ids (see Tile), index = y * size.x + x.
var tiles: PackedByteArray = PackedByteArray()
var player_spawn_cell: Vector2i = PLAYER_SPAWN_CELL
## Each entry: {"enemy_id": String, "cell": Vector2i, "count": int, "radius": float}.
var enemy_spawns: Array[Dictionary] = []


func _init() -> void:
	tiles.resize(size.x * size.y)
	tiles.fill(Tile.GRASS)
	for camp in ENEMY_CAMPS:
		enemy_spawns.append((camp as Dictionary).duplicate())


## Builds the default field layout. Same seed, same map.
static func generate(rng: RandomNumberGenerator) -> MapLayout:
	var layout := MapLayout.new()
	layout._scatter_grass(rng)
	layout._carve_town()
	layout._carve_roads(rng)
	layout._place_lakes(rng)
	layout._place_rocks(rng)
	layout._seal_unreachable()
	return layout


# --- Queries ---------------------------------------------------------------


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


## Tile id at cell; out-of-bounds cells read as ROCK.
func get_tile(cell: Vector2i) -> int:
	if not in_bounds(cell):
		return Tile.ROCK
	return tiles[cell.y * size.x + cell.x]


func set_tile(cell: Vector2i, tile: int) -> void:
	if in_bounds(cell):
		tiles[cell.y * size.x + cell.x] = tile


func is_walkable_cell(cell: Vector2i) -> bool:
	return in_bounds(cell) and is_walkable_tile(get_tile(cell))


static func is_walkable_tile(tile: int) -> bool:
	return tile != Tile.WATER and tile != Tile.ROCK


func walkable_count() -> int:
	var count := 0
	for tile in tiles:
		if is_walkable_tile(tile):
			count += 1
	return count


## Walkable cells reachable from start through edge-sharing (4-way)
## neighbours, as a Dictionary used as a set (cell -> true).
func reachable_from(start: Vector2i) -> Dictionary:
	var seen := {}
	if not is_walkable_cell(start):
		return seen
	var queue: Array[Vector2i] = [start]
	seen[start] = true
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for dir in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var next: Vector2i = cell + dir
			if not seen.has(next) and is_walkable_cell(next):
				seen[next] = true
				queue.append(next)
	return seen


# --- Isometric coordinate helpers -----------------------------------------


## Centre of a cell in world pixels.
static func cell_to_world(cell: Vector2i, tile_size: Vector2i = TILE_SIZE) -> Vector2:
	return Vector2(
		(cell.x - cell.y) * tile_size.x * 0.5,
		(cell.x + cell.y) * tile_size.y * 0.5
	)


## Cell whose diamond contains the world position.
static func world_to_cell(world_pos: Vector2, tile_size: Vector2i = TILE_SIZE) -> Vector2i:
	var a := world_pos.x / (tile_size.x * 0.5)
	var b := world_pos.y / (tile_size.y * 0.5)
	return Vector2i(floori((b + a) * 0.5 + 0.5), floori((b - a) * 0.5 + 0.5))


## The four corners of a cell's diamond (top, right, bottom, left).
static func cell_diamond(cell: Vector2i, tile_size: Vector2i = TILE_SIZE) -> PackedVector2Array:
	var c := cell_to_world(cell, tile_size)
	var half := Vector2(tile_size) * 0.5
	return PackedVector2Array([
		c + Vector2(0, -half.y),
		c + Vector2(half.x, 0),
		c + Vector2(0, half.y),
		c + Vector2(-half.x, 0),
	])


## Outline of the whole map (a big diamond) in world pixels.
func bounds_polygon(tile_size: Vector2i = TILE_SIZE) -> PackedVector2Array:
	var last := size - Vector2i.ONE
	return PackedVector2Array([
		cell_diamond(Vector2i(0, 0), tile_size)[0],
		cell_diamond(Vector2i(last.x, 0), tile_size)[1],
		cell_diamond(last, tile_size)[2],
		cell_diamond(Vector2i(0, last.y), tile_size)[3],
	])


## Axis-aligned bounding box of the map in world pixels.
func world_rect(tile_size: Vector2i = TILE_SIZE) -> Rect2:
	var poly := bounds_polygon(tile_size)
	var rect := Rect2(poly[0], Vector2.ZERO)
	for point in poly:
		rect = rect.expand(point)
	return rect


# --- Generation steps ------------------------------------------------------


func _scatter_grass(rng: RandomNumberGenerator) -> void:
	for i in tiles.size():
		tiles[i] = Tile.GRASS_ALT if rng.randf() < 0.25 else Tile.GRASS


func _carve_town() -> void:
	for y in range(TOWN_RECT.position.y, TOWN_RECT.end.y):
		for x in range(TOWN_RECT.position.x, TOWN_RECT.end.x):
			set_tile(Vector2i(x, y), Tile.DIRT)


## A main road from the town to the east edge, plus a north and a south branch
## that cross it. Roads are two tiles wide and never get obstacles.
func _carve_roads(rng: RandomNumberGenerator) -> void:
	var y := PLAYER_SPAWN_CELL.y
	for x in range(TOWN_RECT.end.x, size.x):
		if x % 3 == 0:
			y = clampi(y + rng.randi_range(-1, 1), 18, 22)
		_carve_road_cell(Vector2i(x, y), Vector2i.DOWN)
	var branch_x := 24
	for row in range(1, 25):
		if row % 3 == 0:
			branch_x = clampi(branch_x + rng.randi_range(-1, 1), 22, 26)
		_carve_road_cell(Vector2i(branch_x, row), Vector2i.RIGHT)
	branch_x = 14
	for row in range(17, size.y):
		if row % 3 == 0:
			branch_x = clampi(branch_x + rng.randi_range(-1, 1), 12, 16)
		_carve_road_cell(Vector2i(branch_x, row), Vector2i.RIGHT)


func _carve_road_cell(cell: Vector2i, width_dir: Vector2i) -> void:
	set_tile(cell, Tile.DIRT)
	set_tile(cell + width_dir, Tile.DIRT)


func _place_lakes(rng: RandomNumberGenerator) -> void:
	for lake in LAKES:
		var center: Vector2i = lake["cell"]
		var radii: Vector2 = lake["radii"]
		var reach := Vector2i(ceili(radii.x) + 1, ceili(radii.y) + 1)
		for y in range(center.y - reach.y, center.y + reach.y + 1):
			for x in range(center.x - reach.x, center.x + reach.x + 1):
				var cell := Vector2i(x, y)
				var d := Vector2(cell - center) / radii
				var jitter := rng.randf_range(-0.25, 0.25)
				if d.length_squared() <= 1.0 + jitter and _can_block(cell):
					set_tile(cell, Tile.WATER)


func _place_rocks(rng: RandomNumberGenerator) -> void:
	var dirs: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	for _cluster in ROCK_CLUSTERS:
		var cell := Vector2i(rng.randi_range(0, size.x - 1), rng.randi_range(0, size.y - 1))
		var length := rng.randi_range(2, 5)
		for _step in length:
			if _can_block(cell):
				set_tile(cell, Tile.ROCK)
			cell += dirs[rng.randi_range(0, dirs.size() - 1)]


## Walkable pockets cut off from the player spawn become rock, so every
## walkable cell can be reached.
func _seal_unreachable() -> void:
	var reachable := reachable_from(player_spawn_cell)
	for y in size.y:
		for x in size.x:
			var cell := Vector2i(x, y)
			if is_walkable_cell(cell) and not reachable.has(cell):
				set_tile(cell, Tile.ROCK)


## True when an obstacle may be placed: in bounds, not on a road or in the
## town, and not near a spawn point.
func _can_block(cell: Vector2i) -> bool:
	if not in_bounds(cell) or get_tile(cell) == Tile.DIRT:
		return false
	if TOWN_RECT.grow(1).has_point(cell):
		return false
	if _chebyshev(cell, player_spawn_cell) <= SPAWN_CLEAR_RADIUS:
		return false
	for spawn in enemy_spawns:
		if _chebyshev(cell, spawn["cell"]) <= SPAWN_CLEAR_RADIUS:
			return false
	return true


static func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
