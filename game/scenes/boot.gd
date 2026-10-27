extends Node
## Entry point. Routes to the login flow, or straight into the game when
## launched with `-- --offline` (or when no login scene exists yet).

const LOGIN_SCENE := "res://ui/login/login.tscn"
const GAME_SCENE := "res://scenes/game.tscn"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--offline" in args or not ResourceLoader.exists(LOGIN_SCENE):
		Session.start_offline()
		get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
	else:
		get_tree().change_scene_to_file.call_deferred(LOGIN_SCENE)
