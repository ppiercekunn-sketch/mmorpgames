extends Node
## Static game data (autoload "GameData"), loaded from res://data/*.json.
## Each JSON file is an object keyed by id. Access: GameData.get_entry("items", "iron_sword").
## Adding a new data table = drop a new JSON file in res://data/; it is loaded by file name.

const DATA_DIR := "res://data"

var tables: Dictionary = {}


func _ready() -> void:
	load_all()


func load_all() -> void:
	tables.clear()
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		push_error("GameData: cannot open %s" % DATA_DIR)
		return
	for file_name in dir.get_files():
		# Exported builds may list "foo.json.remap"-style names; only plain json here.
		if file_name.get_extension() != "json":
			continue
		var table_name := file_name.get_basename()
		var text := FileAccess.get_file_as_string(DATA_DIR.path_join(file_name))
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("GameData: %s is not a JSON object" % file_name)
			continue
		tables[table_name] = parsed


func get_table(table_name: String) -> Dictionary:
	return tables.get(table_name, {})


func get_entry(table_name: String, id: String) -> Dictionary:
	return get_table(table_name).get(id, {})
