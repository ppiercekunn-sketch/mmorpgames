extends Node2D
## Placeholder level-up effect: an expanding golden ring and rising text.
## Add as a child of the actor that levelled; frees itself when done.

const DURATION := 1.4

var text: String = "LEVEL UP!"

var _t: float = 0.0


func _ready() -> void:
	z_index = 10


func _process(delta: float) -> void:
	_t += delta
	if _t >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := _t / DURATION
	var alpha := 1.0 - k
	var gold := Color(1.0, 0.85, 0.3, alpha)
	draw_set_transform(Vector2(0, -12), 0.0, Vector2(1.0, 0.5))
	draw_arc(Vector2.ZERO, 12.0 + 70.0 * k, 0.0, TAU, 48, gold, 4.0 * alpha + 1.0)
	draw_arc(Vector2.ZERO, 6.0 + 40.0 * k, 0.0, TAU, 32, Color(1, 1, 0.8, alpha), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var y := -48.0 - 30.0 * k
	var font := ThemeDB.fallback_font
	draw_string_outline(font, Vector2(-80, y), text, HORIZONTAL_ALIGNMENT_CENTER,
		160, 16, 4, Color(0.3, 0.15, 0.0, alpha))
	draw_string(font, Vector2(-80, y), text, HORIZONTAL_ALIGNMENT_CENTER, 160, 16, gold)
