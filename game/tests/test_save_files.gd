extends TestCase
## SaveGame slot files: write/read, atomic-write recovery, corrupt files,
## delete. Uses its own directory so real saves are never touched.

const DIR := "user://test_saves"


func _clean() -> void:
	for slot in range(1, SaveGame.SLOT_COUNT + 1):
		SaveGame.delete_slot(slot, DIR)
	if DirAccess.dir_exists_absolute(DIR):
		DirAccess.remove_absolute(DIR)


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _save(char_name: String, level: int) -> Dictionary:
	var data := SaveGame.new_save(char_name, "virgo")
	data["character"]["level"] = level
	return data


func test_write_then_read_slot() -> void:
	_clean()
	assert_true(not SaveGame.has_slot(1, DIR), "empty before")
	assert_eq(SaveGame.read_slot(1, DIR), {}, "nothing to read")
	assert_eq(SaveGame.write_slot(1, _save("Alpha", 2), DIR), OK, "write ok")
	assert_true(SaveGame.has_slot(1, DIR), "slot exists")
	assert_true(not SaveGame.has_slot(2, DIR), "other slot empty")
	var loaded := SaveGame.read_slot(1, DIR)
	assert_eq(loaded["character"]["name"], "Alpha", "name")
	assert_eq(loaded["character"]["level"], 2, "level")
	assert_true(not FileAccess.file_exists(SaveGame.slot_path(1, DIR) + ".tmp"), "temp file renamed")
	_clean()


func test_overwrite_keeps_backup_of_previous_save() -> void:
	_clean()
	SaveGame.write_slot(2, _save("Beta", 1), DIR)
	assert_eq(SaveGame.write_slot(2, _save("Beta", 5), DIR), OK, "second write ok")
	assert_eq(SaveGame.read_slot(2, DIR)["character"]["level"], 5, "newest save wins")
	var backup_path := SaveGame.slot_path(2, DIR) + ".bak"
	var backup := SaveGame.from_json(FileAccess.get_file_as_string(backup_path))
	assert_eq(backup["character"]["level"], 1, "previous save kept as .bak")
	_clean()


func test_recovers_from_interrupted_write() -> void:
	_clean()
	SaveGame.write_slot(3, _save("Gamma", 3), DIR)
	var path := SaveGame.slot_path(3, DIR)
	# Crash between "main -> bak" and "tmp -> main": only tmp and bak remain.
	DirAccess.rename_absolute(path, path + ".bak")
	_write_text(path + ".tmp", SaveGame.to_json(_save("Gamma", 4)))
	assert_eq(SaveGame.read_slot(3, DIR)["character"]["level"], 4, "complete temp file used")
	# A half-written temp file next to a good main file is ignored.
	SaveGame.write_slot(3, _save("Gamma", 6), DIR)
	_write_text(path + ".tmp", "{\"version\": 1, \"charac")
	assert_eq(SaveGame.read_slot(3, DIR)["character"]["level"], 6, "main file preferred")
	_clean()


func test_corrupt_file_reads_as_empty_but_slot_is_taken() -> void:
	_clean()
	_write_text(SaveGame.slot_path(1, DIR), "garbage{{{ not json")
	assert_true(SaveGame.has_slot(1, DIR), "slot has a file")
	assert_eq(SaveGame.read_slot(1, DIR), {}, "corrupt save not loaded")
	_write_text(SaveGame.slot_path(1, DIR), "{\"version\": 99, \"character\": {}}")
	assert_eq(SaveGame.read_slot(1, DIR), {}, "future version not loaded")
	_clean()


func test_invalid_data_and_slots_are_not_written() -> void:
	_clean()
	assert_eq(SaveGame.write_slot(0, _save("Delta", 1), DIR), ERR_PARAMETER_RANGE_ERROR, "slot 0")
	assert_eq(SaveGame.write_slot(SaveGame.SLOT_COUNT + 1, _save("Delta", 1), DIR),
		ERR_PARAMETER_RANGE_ERROR, "slot too high")
	assert_eq(SaveGame.write_slot(1, {"character": {"name": "?"}}, DIR), ERR_INVALID_DATA, "bad data")
	assert_true(not SaveGame.has_slot(1, DIR), "nothing written")
	_clean()


func test_delete_slot_removes_all_files() -> void:
	_clean()
	SaveGame.write_slot(1, _save("Echo", 1), DIR)
	SaveGame.write_slot(1, _save("Echo", 2), DIR)
	_write_text(SaveGame.slot_path(1, DIR) + ".tmp", "partial")
	assert_eq(SaveGame.delete_slot(1, DIR), OK, "delete ok")
	assert_true(not SaveGame.has_slot(1, DIR), "slot empty")
	assert_eq(SaveGame.read_slot(1, DIR), {}, "nothing left to read")
	_clean()
