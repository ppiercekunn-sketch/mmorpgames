extends Control
## Full-screen backdrop for the login flow: navy gradient, soft gold glow and
## a fixed star field, drawn with _draw() (no textures). Redraws on resize.

const LoginTheme := preload("res://ui/login/login_theme.gd")

const STAR_COUNT := 90
const STAR_SEED := 1337
const BANDS := 24

## Stars as (x, y, radius, alpha) with x/y in 0..1 so they scale with the window.
var _stars: Array[Vector4] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = STAR_SEED
	for _i in STAR_COUNT:
		var radius := rng.randf_range(0.6, 1.8)
		var alpha := rng.randf_range(0.15, 0.6)
		_stars.append(Vector4(rng.randf(), rng.randf(), radius, alpha))
	resized.connect(queue_redraw)


func _draw() -> void:
	# Vertical gradient from navy (top) to near-black (bottom), in bands.
	var band_height := size.y / BANDS
	for i in BANDS:
		var t := float(i) / float(BANDS - 1)
		var color := LoginTheme.NAVY.lerp(LoginTheme.NAVY_DARK.darkened(0.35), t)
		draw_rect(Rect2(0, i * band_height, size.x, band_height + 1.0), color)

	# Soft gold glow behind the title area.
	var center := Vector2(size.x * 0.5, size.y * 0.18)
	for ring in 6:
		var radius := lerpf(size.x * 0.35, size.x * 0.08, ring / 5.0)
		draw_circle(center, radius, Color(LoginTheme.GOLD, 0.018))

	for star in _stars:
		var pos := Vector2(star.x * size.x, star.y * size.y)
		draw_circle(pos, star.z, Color(LoginTheme.TEXT, star.w))
