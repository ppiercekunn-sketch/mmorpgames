class_name CharacterSprite
extends Node2D
## Draws an actor with its CharacterArt image instead of placeholder shapes.
## Added as a child of the actor by try_attach(); the image's bottom-center
## sits on the actor's origin (its feet) and is scaled to `height` pixels.
##
## Still images only, so motion is procedural (CharacterArt.pose): idle
## breathing, a walking bob while the actor's velocity is non-zero, a lunge on
## play_attack(), a tint on flash(), a fade on death. It also draws a soft
## shadow. It draws behind the parent (show_behind_parent), so HP bars, labels
## and rings the actor draws in _draw() stay on top.
##
## Wired automatically to the parent Actor: hp_changed (flash when HP drops),
## died (fade) and, when present, respawned (restore).

const ATTACK_TIME := 0.32
const FLASH_TIME := 0.14
const DEATH_FADE_TIME := 0.5
const WALK_BLEND_SPEED := 6.0
const MOVING_SPEED := 4.0
const SHADOW_COLOR := Color(0, 0, 0, 0.3)
const SHADOW_SQUASH := 0.42
const FLASH_SHADER := """
shader_type canvas_item;

uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	COLOR.rgb = mix(COLOR.rgb, flash_color.rgb, flash_amount);
}
"""

static var _flash_shader: Shader

var art_id: String = ""
## On-screen height of the character in pixels (feet to top of the image).
var height: float = 64.0
## 1.0 = facing right (as drawn), -1.0 = mirrored. Follows the parent's
## velocity; play_attack() can also set it.
var facing: float = 1.0
## Alpha the sprite fades to on death (1.0 when the parent fades itself).
var death_alpha: float = 0.35

var _actor: Actor
var _sprite: Sprite2D
var _material: ShaderMaterial
var _base_scale: float = 1.0
var _size: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _walk: float = 0.0
var _attack_left: float = 0.0
var _flash_left: float = 0.0
var _last_hp: int = -1
var _dead: bool = false
var _fade: Tween


## Adds a CharacterSprite for `art_id` to `parent` and returns it, or returns
## null (adding nothing) when there is no image for that id.
static func try_attach(parent: Node2D, id: String, target_height: float) -> CharacterSprite:
	var texture := CharacterArt.display_texture_for(id, target_height)
	if texture == null:
		return null
	var art := CharacterSprite.new()
	art.name = "CharacterSprite"
	art.setup(id, texture, target_height)
	parent.add_child(art)
	return art


func setup(id: String, texture: Texture2D, target_height: float) -> void:
	art_id = id
	height = target_height
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite"
		# The project default is nearest; downscaled art needs linear filtering.
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(_sprite)
	var content := texture.get_size()
	_sprite.texture = texture
	_sprite.centered = true
	_sprite.offset = CharacterArt.feet_offset(content)
	_base_scale = CharacterArt.scale_for_height(content.y, target_height)
	_size = CharacterArt.display_size(content, target_height)
	_apply_pose()
	queue_redraw()


func _ready() -> void:
	show_behind_parent = true
	_time = randf() * TAU
	_actor = get_parent() as Actor
	if _actor:
		_last_hp = _actor.hp
		_actor.hp_changed.connect(_on_hp_changed)
		_actor.died.connect(_on_died)
		if _actor.has_signal("respawned"):
			_actor.connect("respawned", revive)
		if _actor.is_dead:
			_dead = true
			modulate.a = death_alpha
	if _flash_shader == null:
		_flash_shader = Shader.new()
		_flash_shader.code = FLASH_SHADER
	_material = ShaderMaterial.new()
	_material.shader = _flash_shader
	if _sprite:
		_sprite.material = _material


## Lunge towards `direction_x` (sign used; 0 keeps the current facing).
func play_attack(direction_x: float = 0.0) -> void:
	if direction_x != 0.0:
		facing = signf(direction_x)
	_attack_left = ATTACK_TIME


## Briefly tints the sprite (hit feedback).
func flash(color: Color = Color.WHITE) -> void:
	_flash_left = FLASH_TIME
	if _material:
		_material.set_shader_parameter("flash_color", color)


func play_death() -> void:
	_dead = true
	_attack_left = 0.0
	if _fade:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", death_alpha, DEATH_FADE_TIME)


func revive() -> void:
	_dead = false
	if _fade:
		_fade.kill()
		_fade = null
	modulate.a = 1.0
	if _actor:
		_last_hp = _actor.hp


func _process(delta: float) -> void:
	_time += delta
	_attack_left = maxf(_attack_left - delta, 0.0)
	_flash_left = maxf(_flash_left - delta, 0.0)
	var moving := false
	if _actor and not _dead:
		moving = _actor.velocity.length() > MOVING_SPEED
		if absf(_actor.velocity.x) > 1.0:
			facing = signf(_actor.velocity.x)
	_walk = move_toward(_walk, 1.0 if moving else 0.0, delta * WALK_BLEND_SPEED)
	_apply_pose()


func _apply_pose() -> void:
	if _sprite == null:
		return
	var progress := 0.0
	if _attack_left > 0.0:
		progress = 1.0 - _attack_left / ATTACK_TIME
	var breathing := _time if not _dead else 0.0
	var p := CharacterArt.pose(breathing, _walk, progress, facing, height)
	_sprite.position = p["position"]
	_sprite.scale = (p["scale"] as Vector2) * _base_scale
	_sprite.rotation = p["rotation"]
	_sprite.flip_h = facing < 0.0
	if _material:
		_material.set_shader_parameter("flash_amount", _flash_left / FLASH_TIME)


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, SHADOW_SQUASH))
	draw_circle(Vector2.ZERO, CharacterArt.shadow_radius(_size), SHADOW_COLOR)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _on_hp_changed(current: int, _maximum: int) -> void:
	if _last_hp >= 0 and current < _last_hp:
		flash()
	_last_hp = current


func _on_died(_killer: Node) -> void:
	play_death()
