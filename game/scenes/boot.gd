extends Node
## Entry point. Routes to the title screen (local save slots), or straight
## into a fresh, unsaved game when launched with `-- --offline` (or when the
## title scene is missing). The online login flow (ui/login/) is not routed to.

const TITLE_SCENE := "res://ui/title/title.tscn"
const GAME_SCENE := "res://scenes/game.tscn"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--offline" in args or not ResourceLoader.exists(TITLE_SCENE):
		Session.start_offline()
		get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
	else:
		get_tree().change_scene_to_file.call_deferred(TITLE_SCENE)
