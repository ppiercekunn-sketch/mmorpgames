extends Node2D
## A drop lying on the ground: an item stack or a pile of gold.
## Collected by walking over it, or by clicking it (if the collector is close;
## otherwise the click walks the player there via Events.ground_clicked).
## Clicks follow the world contract: the node is in group "clickable" and has a
## pickable Area2D (non-zero collision_layer), so Zone leaves the click unhandled
## and the Area2D's input_event fires (needs Viewport.physics_object_picking).
## It only reports `collected`; Progression decides what happens and frees it.

signal collected(pickup: Node2D)

const WALK_OVER_RADIUS := 22.0
const CLICK_RADIUS := 18.0
const CLICK_REACH := 72.0
const LIFETIME := 120.0
## After a refused pickup (bag full), wait this long before retrying walk-over.
const RETRY_DELAY := 1.5
## Physics layer 10: unused by world/players/enemies/pets, only for click picking.
const PICK_LAYER := 1 << 9

var item_id: String = ""
var quantity: int = 1
var gold: int = 0
var label_text: String = ""
var color := Color(0.85, 0.85, 0.85)
## The node that collects pickups (the player).
var collector: Node2D

var _age: float = 0.0
var _retry_at: float = 0.0


## Item drop. `rarity_color` tints the bag.
func setup_item(id: String, qty: int, display_name: String, rarity_color: Color) -> void:
	item_id = id
	quantity = qty
	color = rarity_color
	label_text = display_name if qty == 1 else "%s x%d" % [display_name, qty]


func setup_gold(amount: int) -> void:
	gold = amount
	color = Color(1.0, 0.84, 0.2)
	label_text = "%d gold" % amount


func _ready() -> void:
	add_to_group("clickable")
	var area := Area2D.new()
	area.name = "ClickArea"
	area.input_pickable = true
	area.monitoring = false
	area.monitorable = true
	area.collision_layer = PICK_LAYER
	area.collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = CLICK_RADIUS
	shape.shape = circle
	shape.position = Vector2(0, -8)
	area.add_child(shape)
	add_child(area)
	area.input_event.connect(_on_area_input_event)


func is_gold() -> bool:
	return gold > 0


## Called by the receiver when it could not take the drop (bag full).
func refuse() -> void:
	_retry_at = _age + RETRY_DELAY


func _process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME:
		queue_free()
		return
	queue_redraw()


func _physics_process(_delta: float) -> void:
	if _age < _retry_at or not _collector_alive():
		return
	if collector.global_position.distance_to(global_position) <= WALK_OVER_RADIUS:
		collected.emit(self)


func _on_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	get_viewport().set_input_as_handled()
	if not _collector_alive():
		return
	if collector.global_position.distance_to(global_position) <= CLICK_REACH:
		_retry_at = 0.0
		collected.emit(self)
	else:
		# Walk there; walking over it picks it up.
		Events.ground_clicked.emit(global_position)


func _collector_alive() -> bool:
	if not is_instance_valid(collector):
		return false
	var dead: Variant = collector.get("is_dead")
	return not (dead is bool and dead)


func _draw() -> void:
	var bob := sin(_age * 3.0) * 2.0
	var fade := clampf((LIFETIME - _age) / 5.0, 0.2, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 9.0, Color(0, 0, 0, 0.3 * fade))
	draw_set_transform(Vector2(0, bob), 0.0, Vector2.ONE)
	var col := color
	col.a = fade
	if is_gold():
		draw_circle(Vector2(-4, -5), 5.0, col)
		draw_circle(Vector2(4, -6), 5.0, col)
		draw_circle(Vector2(0, -10), 5.0, col.lightened(0.25))
	else:
		# A drawstring bag: round body, tied neck.
		draw_circle(Vector2(0, -7), 8.0, col)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-4, -14), Vector2(4, -14), Vector2(6, -19), Vector2(-6, -19)]),
			col.darkened(0.25))
		draw_line(Vector2(-5, -14), Vector2(5, -14), Color(0.2, 0.12, 0.05, fade), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var font := ThemeDB.fallback_font
	draw_string_outline(font, Vector2(-60, -26), label_text, HORIZONTAL_ALIGNMENT_CENTER,
		120, 10, 3, Color(0, 0, 0, 0.85 * fade))
	draw_string(font, Vector2(-60, -26), label_text, HORIZONTAL_ALIGNMENT_CENTER,
		120, 10, Color(col.r, col.g, col.b, fade).lightened(0.3))
