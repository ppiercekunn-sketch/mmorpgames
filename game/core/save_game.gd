class_name SaveGame
extends RefCounted
## Local save games: the save Dictionary format, validation / migration and
## file I/O for the three save slots (user://saves/slot_<n>.json).
## Pure logic, no autoload or scene dependencies, so tests can use it.
##
## Save format (version 1), plain JSON-friendly data:
##   {
##     "version": 1,
##     "saved_at": int,          # unix time (seconds, UTC)
##     "playtime": float,        # seconds played in this save
##     "character": {"name", "class": "warrior", "birth_sign", "level", "xp", "gold"},
##     "zone": {"id": String, "position": {"x", "y"} or null},
##     "vitals": {"hp": int, "mp": int},     # -1 = full
##     "inventory": {"slots": [{} | {"id", "qty"}, ...], "equipment": {slot: item_id}},
##     "pet": {"id", "level", "xp"} or {},
##   }
## "xp" is XP inside the current level (as in Session.character).
##
## Loading never trusts the file: `parse()` migrates old versions, rejects
## structurally broken saves (with an error message) and replaces bad field
## values with safe defaults. Item ids are checked later against items.json by
## Inventory.set_state().
##
## Writes are atomic: the JSON goes to "<slot>.json.tmp", is read back and
## checked, the previous save is kept as "<slot>.json.bak", then the temp file
## is renamed over the slot file. A crash at any point leaves at least one
## valid file, and read_slot() tries main -> tmp -> bak.
##
## Web export: user:// is backed by IndexedDB (Godot syncs it after files are
## closed), so the same code works in the browser; saves are per browser/origin.

const VERSION := 1
const SLOT_COUNT := 3
const SAVE_DIR := "user://saves"
const CHARACTER_CLASS := "warrior"
const NAME_MIN := 3
const NAME_MAX := 16
## Sanity bounds for numbers read from disk.
const MAX_LEVEL := 999
const MAX_AMOUNT := 1000000000
const MAX_BAG_SLOTS := 256
const MAX_FILE_BYTES := 1048576


# --- Building ------------------------------------------------------------------


## A fresh level-1 save for a new character (empty bag, no position yet).
static func new_save(character_name: String, birth_sign: String) -> Dictionary:
	return {
		"version": VERSION,
		"saved_at": 0,
		"playtime": 0.0,
		"character": {
			"name": character_name.strip_edges(),
			"class": CHARACTER_CLASS,
			"birth_sign": birth_sign,
			"level": 1,
			"xp": 0,
			"gold": 0,
		},
		"zone": {"id": "", "position": null},
		"vitals": {"hp": -1, "mp": -1},
		"inventory": {"slots": [], "equipment": {}},
		"pet": {},
	}


## "" when the name is fine, else a player-facing message.
static func validate_character_name(character_name: String) -> String:
	var value := character_name.strip_edges()
	if value.length() < NAME_MIN or value.length() > NAME_MAX:
		return "Name must be %d-%d characters." % [NAME_MIN, NAME_MAX]
	var regex := RegEx.create_from_string("^[A-Za-z0-9]+$")
	if regex.search(value) == null:
		return "Use only letters and digits."
	return ""


# --- Accessors (on parsed saves) -------------------------------------------------


## Saved world position, or null when the save has none.
static func get_position(data: Dictionary) -> Variant:
	var zone: Variant = data.get("zone", {})
	if not zone is Dictionary:
		return null
	var pos: Variant = (zone as Dictionary).get("position")
	if not pos is Dictionary:
		return null
	var x: Variant = (pos as Dictionary).get("x")
	var y: Variant = (pos as Dictionary).get("y")
	if not _is_number(x) or not _is_number(y):
		return null
	return Vector2(float(x), float(y))


static func get_zone_id(data: Dictionary) -> String:
	var zone: Variant = data.get("zone", {})
	return str((zone as Dictionary).get("id", "")) if zone is Dictionary else ""


# --- Serialization ---------------------------------------------------------------


## JSON text for a save (sanitized first). Returns "" if the data is invalid.
static func to_json(data: Dictionary) -> String:
	var result := parse(data)
	if result["error"] != "":
		return ""
	return JSON.stringify(result["data"], "\t")


## Parses JSON text into a valid, current-version save; {} when the text is
## not JSON or not a usable save. Never prints errors (corrupt files are expected).
static func from_json(text: String) -> Dictionary:
	if text.strip_edges() == "":
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var result := parse(json.data)
	return result["data"] if result["error"] == "" else {}


## Validates and migrates raw save data (e.g. freshly parsed JSON).
## Returns {"data": Dictionary, "error": String}; on error "data" is {}.
static func parse(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return _fail("Save is not an object.")
	var data: Dictionary = (raw as Dictionary).duplicate(true)
	var version_value: Variant = data.get("version", 0)
	if not _is_number(version_value):
		return _fail("Save version is not a number.")
	var version := int(version_value)
	if version < 0:
		return _fail("Save version %d is invalid." % version)
	if version > VERSION:
		return _fail("Save was made by a newer version of the game (v%d)." % version)
	data = migrate(data, version)
	return sanitize(data)


## Upgrades `data` from `from_version` to VERSION, one step at a time.
## v0 = no "version" field: the flat Session.character shape
## ({name, birth_sign, level, xp, gold}) used before local saves existed.
static func migrate(data: Dictionary, from_version: int) -> Dictionary:
	var out := data
	var version := from_version
	while version < VERSION:
		match version:
			0:
				out = _migrate_v0_to_v1(out)
		version += 1
	out["version"] = VERSION
	return out


## Checks a current-version save and returns {"data", "error"} with every field
## coerced to the expected type. Broken structure (no character, bad name) is
## an error; bad individual values fall back to defaults.
static func sanitize(data: Dictionary) -> Dictionary:
	var character: Variant = data.get("character")
	if not character is Dictionary:
		return _fail("Save has no character.")
	var char_name: Variant = (character as Dictionary).get("name")
	if not char_name is String or validate_character_name(char_name) != "":
		return _fail("Save has an invalid character name.")
	var birth_sign: Variant = (character as Dictionary).get("birth_sign")
	if not birth_sign is String or (birth_sign as String).strip_edges() == "":
		return _fail("Save has no birth sign.")

	var clean := new_save(char_name, (birth_sign as String).strip_edges())
	var c: Dictionary = clean["character"]
	c["level"] = _int_in(character.get("level"), 1, 1, MAX_LEVEL)
	c["xp"] = _int_in(character.get("xp"), 0, 0, MAX_AMOUNT)
	c["gold"] = _int_in(character.get("gold"), 0, 0, MAX_AMOUNT)

	clean["saved_at"] = _int_in(data.get("saved_at"), 0, 0, 1 << 40)
	var playtime: Variant = data.get("playtime", 0.0)
	clean["playtime"] = maxf(float(playtime), 0.0) if _is_number(playtime) else 0.0

	var zone: Variant = data.get("zone", {})
	if zone is Dictionary:
		var zone_id: Variant = (zone as Dictionary).get("id", "")
		clean["zone"]["id"] = zone_id if zone_id is String else ""
		var saved_pos: Variant = get_position(data)
		if saved_pos != null:
			var pos: Vector2 = saved_pos
			clean["zone"]["position"] = {"x": pos.x, "y": pos.y}

	var vitals: Variant = data.get("vitals", {})
	if vitals is Dictionary:
		clean["vitals"]["hp"] = _int_in((vitals as Dictionary).get("hp"), -1, -1, MAX_AMOUNT)
		clean["vitals"]["mp"] = _int_in((vitals as Dictionary).get("mp"), -1, -1, MAX_AMOUNT)

	clean["inventory"] = _sanitize_inventory(data.get("inventory", {}))
	clean["pet"] = _sanitize_pet(data.get("pet", {}))
	return {"data": clean, "error": ""}


# --- Files ---------------------------------------------------------------------


static func is_valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= SLOT_COUNT


static func slot_path(slot: int, dir: String = SAVE_DIR) -> String:
	return dir.path_join("slot_%d.json" % slot)


## True when any file for the slot exists (even an unreadable one).
static func has_slot(slot: int, dir: String = SAVE_DIR) -> bool:
	if not is_valid_slot(slot):
		return false
	for path in _slot_files(slot, dir):
		if FileAccess.file_exists(path):
			return true
	return false


## The slot's save, or {} when it is empty or no file for it can be read.
static func read_slot(slot: int, dir: String = SAVE_DIR) -> Dictionary:
	if not is_valid_slot(slot):
		return {}
	for path in _slot_files(slot, dir):
		if not FileAccess.file_exists(path):
			continue
		var data := from_json(_read_text(path))
		if not data.is_empty():
			return data
	return {}


## Writes the save atomically (see the class doc). Returns OK or an Error.
static func write_slot(slot: int, data: Dictionary, dir: String = SAVE_DIR) -> Error:
	if not is_valid_slot(slot):
		return ERR_PARAMETER_RANGE_ERROR
	var text := to_json(data)
	if text == "":
		return ERR_INVALID_DATA
	if not DirAccess.dir_exists_absolute(dir):
		var mkdir_err := DirAccess.make_dir_recursive_absolute(dir)
		if mkdir_err != OK:
			return mkdir_err
	var files := _slot_files(slot, dir)
	var path: String = files[0]
	var tmp_path: String = files[1]
	var bak_path: String = files[2]

	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var write_err := file.get_error()
	file.close()
	if write_err != OK:
		return write_err
	# Check what actually reached the disk before touching the previous save.
	if from_json(_read_text(tmp_path)).is_empty():
		return ERR_FILE_CORRUPT

	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(bak_path)
		var backup_err := DirAccess.rename_absolute(path, bak_path)
		if backup_err != OK:
			return backup_err
	return DirAccess.rename_absolute(tmp_path, path)


## Removes every file of the slot. Returns OK when nothing is left.
static func delete_slot(slot: int, dir: String = SAVE_DIR) -> Error:
	if not is_valid_slot(slot):
		return ERR_PARAMETER_RANGE_ERROR
	var result := OK
	for path in _slot_files(slot, dir):
		if FileAccess.file_exists(path):
			var err := DirAccess.remove_absolute(path)
			if err != OK:
				result = err
	return result


# --- Internals -----------------------------------------------------------------


## Main file first, then the temp file of an interrupted write, then the backup.
static func _slot_files(slot: int, dir: String) -> Array[String]:
	var path := slot_path(slot, dir)
	var files: Array[String] = [path, path + ".tmp", path + ".bak"]
	return files


static func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES:
		return ""
	return file.get_as_text()


static func _fail(message: String) -> Dictionary:
	return {"data": {}, "error": message}


static func _is_number(value: Variant) -> bool:
	var kind := typeof(value)
	if kind == TYPE_INT:
		return true
	return kind == TYPE_FLOAT and is_finite(value)


static func _int_in(value: Variant, fallback: int, lo: int, hi: int) -> int:
	if not _is_number(value):
		return fallback
	return clampi(int(value), lo, hi)


static func _sanitize_inventory(raw: Variant) -> Dictionary:
	var out := {"slots": [], "equipment": {}}
	if not raw is Dictionary:
		return out
	var slots: Variant = (raw as Dictionary).get("slots", [])
	if slots is Array:
		for entry in (slots as Array).slice(0, MAX_BAG_SLOTS):
			out["slots"].append(_sanitize_stack(entry))
	var equipment: Variant = (raw as Dictionary).get("equipment", {})
	if equipment is Dictionary:
		for slot in equipment:
			var item_id: Variant = equipment[slot]
			if slot is String and item_id is String and item_id != "":
				out["equipment"][slot] = item_id
	return out


## {} for an empty or broken slot, else {"id": String, "qty": int >= 1}.
static func _sanitize_stack(entry: Variant) -> Dictionary:
	if not entry is Dictionary:
		return {}
	var item_id: Variant = (entry as Dictionary).get("id")
	var qty := _int_in((entry as Dictionary).get("qty"), 0, 0, MAX_AMOUNT)
	if not item_id is String or item_id == "" or qty < 1:
		return {}
	return {"id": item_id, "qty": qty}


static func _sanitize_pet(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var pet_id: Variant = (raw as Dictionary).get("id")
	if not pet_id is String or pet_id == "":
		return {}
	return {
		"id": pet_id,
		"level": _int_in((raw as Dictionary).get("level"), 1, 1, MAX_LEVEL),
		"xp": _int_in((raw as Dictionary).get("xp"), 0, 0, MAX_AMOUNT),
	}


static func _migrate_v0_to_v1(old: Dictionary) -> Dictionary:
	var out := new_save(str(old.get("name", "")), str(old.get("birth_sign", "")))
	for key in ["level", "xp", "gold"]:
		if old.has(key):
			out["character"][key] = old[key]
	return out
