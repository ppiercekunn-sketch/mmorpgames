extends Node2D
## Short-lived ring drawn where the player clicked to move. Frees itself.

const DURATION := 0.45
const START_RADIUS := 16.0
const END_RADIUS := 4.0
const COLOR := Color(1.0, 0.95, 0.55)

var _age: float = 0.0


func _process(delta: float) -> void:
	_age += delta
	if _age >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := clampf(_age / DURATION, 0.0, 1.0)
	var color := Color(COLOR, 1.0 - t)
	# Squash vertically so the ring lies flat on the isometric ground.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_arc(Vector2.ZERO, lerpf(START_RADIUS, END_RADIUS, t), 0.0, TAU, 24, color, 2.0)
	draw_circle(Vector2.ZERO, 2.5, color)
