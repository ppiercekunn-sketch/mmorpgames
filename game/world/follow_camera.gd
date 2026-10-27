class_name FollowCamera
extends Camera2D
## Camera that smoothly follows a target, zooms with the mouse wheel and stays
## inside the map. Usage:
##   var camera := FollowCamera.new()
##   add_child(camera)
##   camera.set_bounds(zone.get_map_rect())
##   camera.follow(player)

@export var min_zoom: float = 0.75
@export var max_zoom: float = 2.0
## Multiplicative zoom change per wheel notch.
@export var zoom_step: float = 1.1
## How fast the zoom eases towards the wheel-selected value.
@export var zoom_speed: float = 10.0
@export var follow_speed: float = 6.0

var target: Node2D
var _target_zoom: float = 1.0
var _bounds: Rect2 = Rect2()


func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = follow_speed
	_target_zoom = clampf(zoom.x, _effective_min_zoom(), max_zoom)
	zoom = Vector2(_target_zoom, _target_zoom)
	make_current()


## Starts following target (snaps to it immediately). Pass null to stop.
func follow(new_target: Node2D) -> void:
	target = new_target
	if target != null and is_inside_tree():
		global_position = target.global_position
		reset_smoothing()


## Keeps the view inside rect (world pixels). An empty rect removes the limits.
func set_bounds(rect: Rect2) -> void:
	_bounds = rect
	limit_smoothed = true
	if rect.has_area():
		limit_left = floori(rect.position.x)
		limit_top = floori(rect.position.y)
		limit_right = ceili(rect.end.x)
		limit_bottom = ceili(rect.end.y)
	else:
		limit_left = -10000000
		limit_top = -10000000
		limit_right = 10000000
		limit_bottom = 10000000
	_target_zoom = clampf(_target_zoom, _effective_min_zoom(), max_zoom)


func set_zoom_level(value: float) -> void:
	_target_zoom = clampf(value, _effective_min_zoom(), max_zoom)


func get_zoom_level() -> float:
	return _target_zoom


func _process(delta: float) -> void:
	if is_instance_valid(target):
		global_position = target.global_position
	var current := zoom.x
	if not is_equal_approx(current, _target_zoom):
		var next := lerpf(current, _target_zoom, 1.0 - exp(-zoom_speed * delta))
		if absf(next - _target_zoom) < 0.001:
			next = _target_zoom
		zoom = Vector2(next, next)


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		set_zoom_level(_target_zoom * zoom_step)
		get_viewport().set_input_as_handled()
	elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		set_zoom_level(_target_zoom / zoom_step)
		get_viewport().set_input_as_handled()


## Never zoom out so far that the view is larger than the map.
func _effective_min_zoom() -> float:
	if not _bounds.has_area() or not is_inside_tree():
		return min_zoom
	var view := get_viewport_rect().size
	return maxf(min_zoom, maxf(view.x / _bounds.size.x, view.y / _bounds.size.y))
