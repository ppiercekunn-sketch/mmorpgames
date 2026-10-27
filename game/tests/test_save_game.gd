extends TestCase
## SaveGame format: round trip, version / migration, invalid data rejected.


func _sample() -> Dictionary:
	var data := SaveGame.new_save("Hero42", "leo")
	data["character"]["level"] = 4
	data["character"]["xp"] = 57
	data["character"]["gold"] = 321
	data["saved_at"] = 1760000000
	data["playtime"] = 3723.5
	data["zone"] = {"id": "field_01", "position": {"x": 120.5, "y": -48.0}}
	data["vitals"] = {"hp": 150, "mp": 40}
	data["inventory"] = {
		"slots": [{"id": "hp_potion", "qty": 3}, {}, {"id": "novice_cap", "qty": 1}],
		"equipment": {"weapon": "novice_sword"},
	}
	data["pet"] = {"id": "star_pup", "level": 2, "xp": 15}
	return data


func test_round_trip_through_json() -> void:
	var text := SaveGame.to_json(_sample())
	assert_true(text != "", "serialized")
	var loaded := SaveGame.from_json(text)
	assert_eq(loaded.get("version"), SaveGame.VERSION, "version")
	var c: Dictionary = loaded["character"]
	assert_eq(c["name"], "Hero42", "name")
	assert_eq(c["class"], "warrior", "class")
	assert_eq(c["birth_sign"], "leo", "sign")
	assert_eq(c["level"], 4, "level")
	assert_eq(c["xp"], 57, "xp")
	assert_eq(c["gold"], 321, "gold")
	assert_eq(typeof(c["level"]), TYPE_INT, "JSON floats become ints")
	assert_eq(loaded["saved_at"], 1760000000, "saved_at")
	assert_near(loaded["playtime"], 3723.5, 0.001, "playtime")
	assert_eq(SaveGame.get_zone_id(loaded), "field_01", "zone id")
	assert_eq(SaveGame.get_position(loaded), Vector2(120.5, -48.0), "position")
	assert_eq(loaded["vitals"], {"hp": 150, "mp": 40}, "vitals")
	assert_eq(loaded["inventory"]["slots"][0], {"id": "hp_potion", "qty": 3}, "slot 0")
	assert_eq(loaded["inventory"]["slots"][1], {}, "slot 1 empty")
	assert_eq(loaded["inventory"]["equipment"], {"weapon": "novice_sword"}, "equipment")
	assert_eq(loaded["pet"], {"id": "star_pup", "level": 2, "xp": 15}, "pet")


func test_round_trip_is_stable() -> void:
	var once := SaveGame.from_json(SaveGame.to_json(_sample()))
	var twice := SaveGame.from_json(SaveGame.to_json(once))
	assert_eq(twice, once, "parse(serialize(x)) == x for a parsed save")


func test_new_save_is_valid_and_has_no_position() -> void:
	var result := SaveGame.parse(SaveGame.new_save("Nova", "aries"))
	assert_eq(result["error"], "", "no error")
	assert_eq(SaveGame.get_position(result["data"]), null, "no position")
	assert_eq(result["data"]["character"]["level"], 1, "level 1")


func test_unversioned_save_is_migrated_from_v0() -> void:
	var legacy := {"name": "OldHero", "birth_sign": "taurus", "level": 3, "xp": 20, "gold": 9}
	var result := SaveGame.parse(legacy)
	assert_eq(result["error"], "", "migrated without error")
	var data: Dictionary = result["data"]
	assert_eq(data["version"], SaveGame.VERSION, "now current version")
	assert_eq(data["character"]["name"], "OldHero", "name kept")
	assert_eq(data["character"]["level"], 3, "level kept")
	assert_eq(data["character"]["gold"], 9, "gold kept")
	assert_eq(data["inventory"]["slots"], [], "empty bag")


func test_newer_version_is_rejected() -> void:
	var data := _sample()
	data["version"] = SaveGame.VERSION + 1
	var result := SaveGame.parse(data)
	assert_true(result["error"] != "", "error reported")
	assert_eq(result["data"], {}, "no data")


func test_bad_version_values_are_rejected() -> void:
	for bad in ["1", -1, null, [1]]:
		var data := _sample()
		data["version"] = bad
		assert_true(SaveGame.parse(data)["error"] != "", "version %s rejected" % str(bad))


func test_corrupt_text_is_rejected() -> void:
	var good := SaveGame.to_json(_sample())
	var truncated := good.left(floori(good.length() * 0.5))
	var cases := ["", "   ", "{", "not json", "[]", "42", "null", truncated]
	for text in cases:
		assert_eq(SaveGame.from_json(text), {}, "rejected: %s" % text.left(20))


func test_structural_problems_are_rejected() -> void:
	var no_character := _sample()
	no_character.erase("character")
	assert_true(SaveGame.parse(no_character)["error"] != "", "missing character")
	var bad_name := _sample()
	bad_name["character"]["name"] = "a b!"
	assert_true(SaveGame.parse(bad_name)["error"] != "", "invalid name")
	var no_sign := _sample()
	no_sign["character"]["birth_sign"] = 5
	assert_true(SaveGame.parse(no_sign)["error"] != "", "invalid sign")
	assert_true(SaveGame.parse("text")["error"] != "", "not a dictionary")
	assert_eq(SaveGame.to_json(no_character), "", "invalid data is not serialized")


func test_bad_field_values_fall_back_to_defaults() -> void:
	var data := _sample()
	data["character"]["level"] = -5
	data["character"]["xp"] = "lots"
	data["character"]["gold"] = INF
	data["playtime"] = -10
	data["zone"] = {"id": 7, "position": {"x": "a", "y": 2}}
	data["vitals"] = "full"
	data["inventory"] = {
		"slots": [{"id": "hp_potion", "qty": 0}, "junk", {"id": 3, "qty": 1}, {"id": "ore", "qty": 2.0}],
		"equipment": {"weapon": 12, "head": "novice_cap"},
	}
	data["pet"] = {"id": "", "level": 3}
	var result := SaveGame.parse(data)
	assert_eq(result["error"], "", "still loads")
	var clean: Dictionary = result["data"]
	assert_eq(clean["character"]["level"], 1, "level clamped")
	assert_eq(clean["character"]["xp"], 0, "xp default")
	assert_eq(clean["character"]["gold"], 0, "non-finite gold default")
	assert_eq(clean["playtime"], 0.0, "playtime clamped")
	assert_eq(SaveGame.get_zone_id(clean), "", "zone id default")
	assert_eq(SaveGame.get_position(clean), null, "bad position dropped")
	assert_eq(clean["vitals"], {"hp": -1, "mp": -1}, "vitals default")
	assert_eq(clean["inventory"]["slots"], [{}, {}, {}, {"id": "ore", "qty": 2}], "bad stacks emptied")
	assert_eq(clean["inventory"]["equipment"], {"head": "novice_cap"}, "bad gear dropped")
	assert_eq(clean["pet"], {}, "pet without id dropped")


func test_character_name_rules() -> void:
	assert_eq(SaveGame.validate_character_name("Hero1"), "", "valid")
	assert_eq(SaveGame.validate_character_name("  Abc  "), "", "trimmed")
	assert_true(SaveGame.validate_character_name("ab") != "", "too short")
	assert_true(SaveGame.validate_character_name("a".repeat(17)) != "", "too long")
	assert_true(SaveGame.validate_character_name("bad name") != "", "space")
	assert_true(SaveGame.validate_character_name("Héro") != "", "non-ascii letter")
