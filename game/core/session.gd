extends Node
## Session state (autoload "Session").
## Filled by the title screen (local save slots) or the --offline boot path,
## read by the game scene. The account/token fields belong to the unused
## online login flow (ui/login/, net/) and stay empty in the offline game.

const DEFAULT_API_URL := "http://localhost:8000/api"

var api_base_url: String = DEFAULT_API_URL
var token: String = ""
var account: Dictionary = {}
## Current character: {id, name, class, birth_sign, level, xp, gold}
## ("xp" = XP inside the current level). Progression keeps level/xp/gold in sync.
var character: Dictionary = {}
## True when playing without a backend (always, for now: local saves only).
var offline: bool = false
## Save slot (1..SaveGame.SLOT_COUNT) the game autosaves to; -1 = unsaved game.
var save_slot: int = -1
## Parsed save (SaveGame format) for the game scene to restore once it has
## loaded; the game scene clears it after applying. {} = fresh character.
var pending_save: Dictionary = {}


func is_logged_in() -> bool:
	return token != "" or offline


## A fresh, unsaved character (no save slot). Used by `-- --offline` and sandboxes.
func start_offline(character_name: String = "Wanderer", birth_sign: String = "aries") -> void:
	offline = true
	save_slot = -1
	pending_save = {}
	character = {
		"id": 0,
		"name": character_name,
		"class": "warrior",
		"birth_sign": birth_sign,
		"level": 1,
		"xp": 0,
		"gold": 0,
	}


## A new character that autosaves into `slot`.
func start_new_game(slot: int, character_name: String, birth_sign: String) -> void:
	start_offline(character_name, birth_sign)
	save_slot = slot


## Continues a parsed save (SaveGame.read_slot() output) from `slot`.
func start_from_save(slot: int, data: Dictionary) -> void:
	var saved: Dictionary = data.get("character", {})
	start_offline(str(saved.get("name", "Wanderer")), str(saved.get("birth_sign", "aries")))
	for key in ["level", "xp", "gold"]:
		character[key] = int(saved.get(key, character[key]))
	save_slot = slot
	pending_save = data.duplicate(true)


func has_save_slot() -> bool:
	return save_slot > 0


func clear() -> void:
	token = ""
	account = {}
	character = {}
	offline = false
	save_slot = -1
	pending_save = {}
