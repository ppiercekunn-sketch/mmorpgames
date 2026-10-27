extends Actor
## Stand-in actor for the progression sandbox: a drawn circle with a name and
## HP bar. Used for the stand-in player and for dummy enemies, so the sandbox
## does not depend on combat/ code. Enemy dummies expose the same `enemy_id`
## property the real Enemy has, plus `xp` / `loot_table` fallbacks that
## Progression reads when enemies.json has no entry for the id.

var enemy_id: String = ""
var xp: int = 0
var loot_table: String = ""
## Mirrors Player.current_target.
var current_target: Actor
var body_color := Color(0.4, 0.6, 1.0)
var radius: float = 12.0


func _ready() -> void:
	super._ready()
	hp_changed.connect(_on_vitals_changed)
	died.connect(_on_died)


func _on_vitals_changed(_current: int, _maximum: int) -> void:
	queue_redraw()


func _on_died(_killer: Node) -> void:
	queue_redraw()


func _draw() -> void:
	var col := body_color if not is_dead else Color(0.35, 0.35, 0.35, 0.6)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, radius + 2.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(Vector2(0, -radius), radius, col)
	draw_arc(Vector2(0, -radius), radius, 0.0, TAU, 24, col.darkened(0.4), 2.0)
	var font := ThemeDB.fallback_font
	var label := "%s Lv%d" % [display_name, stats.level]
	var top := -radius * 2.0 - 10.0
	draw_string_outline(font, Vector2(-60, top), label, HORIZONTAL_ALIGNMENT_CENTER,
		120, 11, 3, Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(-60, top), label, HORIZONTAL_ALIGNMENT_CENTER, 120, 11)
	if not is_dead:
		var ratio := clampf(float(hp) / float(maxi(stats.max_hp(), 1)), 0.0, 1.0)
		draw_rect(Rect2(-16, top + 3, 32, 4), Color(0.15, 0.05, 0.05, 0.85))
		draw_rect(Rect2(-16, top + 3, 32 * ratio, 4), Color(0.85, 0.25, 0.25))
