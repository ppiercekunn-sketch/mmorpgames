extends RefCounted
## Placeholder isometric ground art, generated at runtime (no binary assets).
## build_tile_set() returns a TileSet with one atlas source whose tiles are
## laid out in a single row: atlas coords (tile_id, 0) for each
## MapLayout.Tile. Blocked tiles (water, rock) get a collision polygon on
## physics layer 1 ("world").

const SOURCE_ID := 0
## Collision polygons are shrunk a little so a body can squeeze through
## one-tile gaps that navigation allows.
const COLLISION_SCALE := 0.75
const WORLD_PHYSICS_LAYER := 1

const GRASS := Color(0.33, 0.56, 0.27)
const GRASS_ALT := Color(0.38, 0.61, 0.30)
const DIRT := Color(0.62, 0.48, 0.31)
const WATER := Color(0.21, 0.43, 0.70)
const ROCK := Color(0.52, 0.52, 0.55)


static func atlas_coords(tile: int) -> Vector2i:
	return Vector2i(tile, 0)


static func build_tile_set(tile_size: Vector2i) -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	tile_set.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	tile_set.tile_size = tile_size
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(0, WORLD_PHYSICS_LAYER)
	tile_set.set_physics_layer_collision_mask(0, 0)

	var source := TileSetAtlasSource.new()
	source.texture = build_atlas_texture(tile_size)
	source.texture_region_size = tile_size
	tile_set.add_source(source, SOURCE_ID)

	var collision := diamond(tile_size, COLLISION_SCALE)
	for value in MapLayout.Tile.values():
		var tile := int(value)
		source.create_tile(atlas_coords(tile))
		if not MapLayout.is_walkable_tile(tile):
			var data := source.get_tile_data(atlas_coords(tile), 0)
			data.add_collision_polygon(0)
			data.set_collision_polygon_points(0, 0, collision)
	return tile_set


## Diamond centred on (0, 0), the shape of one isometric tile.
static func diamond(tile_size: Vector2i, factor: float = 1.0) -> PackedVector2Array:
	var half := Vector2(tile_size) * 0.5 * factor
	return PackedVector2Array([
		Vector2(0, -half.y), Vector2(half.x, 0), Vector2(0, half.y), Vector2(-half.x, 0),
	])


static func build_atlas_texture(tile_size: Vector2i) -> ImageTexture:
	var tile_count := MapLayout.Tile.size()
	var image := Image.create(tile_size.x * tile_count, tile_size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for value in MapLayout.Tile.values():
		_paint_tile(image, int(value), tile_size, rng)
	return ImageTexture.create_from_image(image)


static func _paint_tile(
	image: Image, tile: int, tile_size: Vector2i, rng: RandomNumberGenerator
) -> void:
	var origin_x := tile * tile_size.x
	var half := Vector2(tile_size) * 0.5
	for py in tile_size.y:
		for px in tile_size.x:
			# Normalised diamond distance: <= 1 inside the tile.
			var offset := Vector2(px + 0.5, py + 0.5) - half
			var d := absf(offset.x) / half.x + absf(offset.y) / half.y
			if d > 1.0:
				continue
			var color := _tile_color(tile, offset, half, rng)
			if d > 0.93:
				color = color.darkened(0.12)
			image.set_pixel(origin_x + px, py, color)


static func _tile_color(
	tile: int, offset: Vector2, half: Vector2, rng: RandomNumberGenerator
) -> Color:
	var noise := rng.randf_range(-0.05, 0.05)
	if tile == MapLayout.Tile.GRASS_ALT:
		if rng.randf() < 0.015:
			return Color(0.95, 0.9, 0.45)
		return _vary(GRASS_ALT, noise)
	if tile == MapLayout.Tile.DIRT:
		return _vary(DIRT, noise)
	if tile == MapLayout.Tile.WATER:
		# Light horizontal wave streaks.
		if int(offset.y + half.y) % 6 == 0 and int(offset.x + half.x) % 12 < 5:
			return WATER.lightened(0.25)
		return _vary(WATER, noise * 0.5)
	if tile == MapLayout.Tile.ROCK:
		# A grey boulder sitting on darker grass.
		var r := absf(offset.x) / (half.x * 0.7) + absf(offset.y + 2.0) / (half.y * 0.8)
		if r > 1.0:
			return GRASS.darkened(0.1)
		return ROCK.lightened(0.2) if offset.y < -2.0 else ROCK.darkened(absf(noise))
	return _vary(GRASS, noise)


static func _vary(color: Color, amount: float) -> Color:
	return color.lightened(amount) if amount > 0.0 else color.darkened(-amount)
