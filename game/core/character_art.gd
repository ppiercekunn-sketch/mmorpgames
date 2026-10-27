class_name CharacterArt
extends RefCounted
## Optional character images (res://art/characters/<id>.png, see art/README.md).
## Actors call CharacterSprite.try_attach(); when no image exists they keep
## drawing their placeholder shapes.
##
## The math helpers (scale_for_height, feet_offset, pose, ...) are pure so
## they can be tested headless.

const ART_DIR := "res://art/characters"
## Runtime textures are downscaled to this multiple of the on-screen height,
## which keeps them sharp up to the follow camera's max zoom (2x).
const SUPERSAMPLE := 2.0
const BREATH_SPEED := 2.4
const STEP_SPEED := 11.0

## id -> Texture2D, or null when the file does not exist.
static var _textures: Dictionary = {}
## "id@height" -> Texture2D prepared for display.
static var _display_textures: Dictionary = {}


static func path_for(art_id: String) -> String:
	return ART_DIR.path_join(art_id + ".png")


## The imported texture for `art_id`, or null when there is no image. Cached.
static func texture_for(art_id: String) -> Texture2D:
	if art_id == "":
		return null
	if _textures.has(art_id):
		return _textures[art_id]
	var texture: Texture2D = null
	var path := path_for(art_id)
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_textures[art_id] = texture
	return texture


static func has_art(art_id: String) -> bool:
	return texture_for(art_id) != null


## A copy of the texture trimmed to its opaque pixels and downscaled to
## SUPERSAMPLE x `target_height` (high-quality filtering, since the project
## default is nearest). Falls back to the raw texture when its pixels cannot be
## read back. Cached per id and height.
static func display_texture_for(art_id: String, target_height: float) -> Texture2D:
	var texture := texture_for(art_id)
	if texture == null:
		return null
	var key := "%s@%d" % [art_id, roundi(target_height)]
	if _display_textures.has(key):
		return _display_textures[key]
	var prepared: Texture2D = texture
	var image := texture.get_image()
	if image != null and not image.is_empty():
		image = _prepare_image(image, target_height)
		if image != null:
			prepared = ImageTexture.create_from_image(image)
	_display_textures[key] = prepared
	return prepared


static func _prepare_image(source: Image, target_height: float) -> Image:
	var image := source.duplicate() as Image
	if image.is_compressed() and image.decompress() != OK:
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var used := image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return null
	if used.size != image.get_size():
		image = image.get_region(used)
	var size := supersampled_size(Vector2(image.get_size()), target_height, SUPERSAMPLE)
	if size.y < image.get_height():
		image.fix_alpha_edges()
		image.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	return image


# --- Pure helpers ----------------------------------------------------------------


## Uniform scale that makes an image `content_height` pixels tall appear
## `target_height` pixels tall.
static func scale_for_height(content_height: float, target_height: float) -> float:
	if content_height <= 0.0:
		return 1.0
	return target_height / content_height


## Sprite2D.offset (centered sprite, texture pixels) that puts the image's
## bottom-center on the node origin, i.e. the actor's feet.
static func feet_offset(content_size: Vector2) -> Vector2:
	return Vector2(0.0, -content_size.y / 2.0)


## On-screen size of an image scaled to `target_height`.
static func display_size(content_size: Vector2, target_height: float) -> Vector2:
	return content_size * scale_for_height(content_size.y, target_height)


## Pixel size to downscale an image to so it is `factor` x the on-screen
## height. Never upscales; keeps the aspect ratio; at least 1x1.
static func supersampled_size(
	content_size: Vector2, target_height: float, factor: float
) -> Vector2i:
	var height := minf(content_size.y, ceilf(target_height * factor))
	var width := content_size.x * scale_for_height(content_size.y, height)
	return Vector2i(maxi(roundi(width), 1), maxi(roundi(height), 1))


## Radius of the shadow ellipse (before the vertical squash) for a sprite.
static func shadow_radius(size: Vector2) -> float:
	return clampf(size.x * 0.3, size.y * 0.18, size.y * 0.5)


## Attack motion over progress 0..1: a short wind-up back (negative), a lunge
## forward peaking at 1.0 halfway, then a return to rest (0 at both ends).
static func attack_curve(progress: float) -> float:
	var p := clampf(progress, 0.0, 1.0)
	if p < 0.25:
		return -0.3 * (p / 0.25)
	if p < 0.5:
		return lerpf(-0.3, 1.0, (p - 0.25) / 0.25)
	return 1.0 - (p - 0.5) / 0.5


## Procedural pose for a still image. `walk` blends 0 (idle breathing) to 1
## (walking bob and tilt); `attack_progress` is 0..1 during an attack, else 0.
## Returns {"position": Vector2, "scale": Vector2, "rotation": float}, all
## relative to the feet; scale multiplies the base scale.
static func pose(
	time: float, walk: float, attack_progress: float, facing: float, height: float
) -> Dictionary:
	var idle := 1.0 - walk
	var breathe := sin(time * BREATH_SPEED)
	var step := sin(time * STEP_SPEED)
	var pose_scale := Vector2(1.0 - 0.015 * breathe * idle, 1.0 + 0.03 * breathe * idle)
	var position := Vector2(0.0, -absf(step) * height * 0.05 * walk)
	var rotation := step * 0.07 * walk
	if attack_progress > 0.0:
		var a := attack_curve(attack_progress)
		position.x += facing * height * 0.2 * a
		pose_scale *= Vector2(1.0 + 0.12 * absf(a), 1.0 - 0.1 * absf(a))
		rotation += facing * 0.12 * a
	return {"position": position, "scale": pose_scale, "rotation": rotation}
