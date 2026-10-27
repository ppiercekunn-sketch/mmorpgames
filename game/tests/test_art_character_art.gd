extends TestCase


func test_scale_for_height() -> void:
	assert_near(CharacterArt.scale_for_height(512.0, 64.0), 0.125)
	assert_near(CharacterArt.scale_for_height(128.0, 110.0), 110.0 / 128.0)
	assert_near(CharacterArt.scale_for_height(0.0, 64.0), 1.0, 0.0001, "zero height")


func test_feet_offset_puts_bottom_center_on_origin() -> void:
	var size := Vector2(300.0, 512.0)
	var offset := CharacterArt.feet_offset(size)
	assert_eq(offset, Vector2(0.0, -256.0))
	# A centered sprite spans offset +- size/2: bottom edge at y = 0, centred on x = 0.
	assert_near(offset.y + size.y / 2.0, 0.0)
	assert_near(offset.x, 0.0)


func test_display_size_keeps_aspect() -> void:
	var size := CharacterArt.display_size(Vector2(256.0, 512.0), 64.0)
	assert_near(size.x, 32.0)
	assert_near(size.y, 64.0)


func test_supersampled_size_never_upscales() -> void:
	assert_eq(CharacterArt.supersampled_size(Vector2(512, 512), 64.0, 2.0), Vector2i(128, 128))
	assert_eq(CharacterArt.supersampled_size(Vector2(400, 800), 110.0, 2.0), Vector2i(110, 220))
	assert_eq(CharacterArt.supersampled_size(Vector2(60, 90), 64.0, 2.0), Vector2i(60, 90))


func test_attack_curve_shape() -> void:
	assert_near(CharacterArt.attack_curve(0.0), 0.0)
	assert_near(CharacterArt.attack_curve(0.25), -0.3)
	assert_near(CharacterArt.attack_curve(0.5), 1.0)
	assert_near(CharacterArt.attack_curve(1.0), 0.0)
	assert_near(CharacterArt.attack_curve(2.0), 0.0, 0.0001, "clamped")


func test_pose_idle_keeps_feet_planted() -> void:
	var p := CharacterArt.pose(1.3, 0.0, 0.0, 1.0, 64.0)
	assert_eq(p["position"], Vector2.ZERO)
	assert_near(p["rotation"], 0.0)
	var s: Vector2 = p["scale"]
	assert_true(absf(s.y - 1.0) <= 0.03 and absf(s.x - 1.0) <= 0.015, "small breathing")


func test_pose_walk_bobs_up_only() -> void:
	for i in 20:
		var p := CharacterArt.pose(i * 0.07, 1.0, 0.0, 1.0, 64.0)
		var pos: Vector2 = p["position"]
		assert_true(pos.y <= 0.0 and pos.y >= -64.0 * 0.05 - 0.001, "bob within range")


func test_pose_attack_lunges_towards_facing() -> void:
	var right: Vector2 = CharacterArt.pose(0.0, 0.0, 0.5, 1.0, 64.0)["position"]
	var left: Vector2 = CharacterArt.pose(0.0, 0.0, 0.5, -1.0, 64.0)["position"]
	assert_near(right.x, 64.0 * 0.2)
	assert_near(left.x, -64.0 * 0.2)


func test_shadow_radius_clamped() -> void:
	assert_near(CharacterArt.shadow_radius(Vector2(64, 64)), 64.0 * 0.3)
	assert_near(CharacterArt.shadow_radius(Vector2(10, 64)), 64.0 * 0.18)
	assert_near(CharacterArt.shadow_radius(Vector2(300, 64)), 32.0)


func test_missing_art_returns_null() -> void:
	assert_eq(CharacterArt.texture_for(""), null)
	assert_eq(CharacterArt.texture_for("no_such_character_xyz"), null)
	assert_eq(CharacterArt.path_for("wolf"), "res://art/characters/wolf.png")
