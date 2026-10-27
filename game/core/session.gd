extends Node
## Logged-in session state (autoload "Session").
## Filled by the login/character-select flow, read by the game scene.

const DEFAULT_API_URL := "http://localhost:8000/api"

var api_base_url: String = DEFAULT_API_URL
var token: String = ""
var account: Dictionary = {}
## Character payload as returned by the API (see docs/api.md).
var character: Dictionary = {}
## True when playing without a backend (local dev / offline M1 build).
var offline: bool = false


func is_logged_in() -> bool:
	return token != "" or offline


func start_offline(character_name: String = "Wanderer", birth_sign: String = "aries") -> void:
	offline = true
	character = {
		"id": 0,
		"name": character_name,
		"class": "warrior",
		"birth_sign": birth_sign,
		"level": 1,
		"xp": 0,
		"gold": 0,
	}


func clear() -> void:
	token = ""
	account = {}
	character = {}
	offline = false
