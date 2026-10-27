extends Node2D
## Integration scene: assembles world, player, enemies, progression and UI.
## Each system only knows the contracts in docs/ARCHITECTURE.md; this script
## is the one place that wires them together. Also restores the pending local
## save (Session.pending_save) and owns the save manager and pause menu.

const ZONE_SCENE := preload("res://world/zone.tscn")
const PLAYER_SCENE := preload("res://combat/player/player.tscn")
const COMBAT_HUD_SCENE := preload("res://combat/ui/combat_hud.tscn")
const SaveManager := preload("res://scenes/save_manager.gd")
const PauseMenu := preload("res://ui/pause_menu.gd")
const TITLE_SCENE := "res://ui/title/title.tscn"

var zone: Zone
var player: Player
var camera: FollowCamera
var enemy_spawner: EnemySpawner
var progression: Progression
var save_manager: SaveManager
var pause_menu: PauseMenu


func _ready() -> void:
	# Enemies, loot and UI rely on Area2D click picking.
	get_viewport().physics_object_picking = true
	var save_data: Dictionary = Session.pending_save
	Session.pending_save = {}

	# First child, so every other system's _unhandled_input sees Esc before it.
	pause_menu = PauseMenu.new()
	pause_menu.can_save = Session.has_save_slot()
	add_child(pause_menu)

	zone = ZONE_SCENE.instantiate()
	add_child(zone)

	var entities := zone.get_entities_root()
	player = PLAYER_SCENE.instantiate()
	player.display_name = str(Session.character.get("name", "Wanderer"))
	player.global_position = SaveManager.start_position(zone, save_data)
	entities.add_child(player)
	# Respawn at the zone spawn even when the save put the player elsewhere.
	player.set_spawn_point(zone.get_player_spawn())
	Events.player_spawned.emit(player)

	camera = FollowCamera.new()
	add_child(camera)
	camera.set_bounds(zone.get_map_rect())
	camera.follow(player)

	enemy_spawner = EnemySpawner.new()
	add_child(enemy_spawner)
	enemy_spawner.setup(entities)

	progression = Progression.new()
	add_child(progression)
	progression.setup(player, entities)

	# Progression creates its own UI (XP bar, inventory, pet frame).
	add_child(COMBAT_HUD_SCENE.instantiate())

	save_manager = SaveManager.new()
	save_manager.name = "SaveManager"
	add_child(save_manager)
	save_manager.setup(zone, player, progression, save_data)

	pause_menu.save_requested.connect(_on_save_requested)
	pause_menu.quit_requested.connect(_on_quit_requested)


func _on_save_requested() -> void:
	if save_manager.save_now():
		pause_menu.set_status("Game saved.")
	else:
		pause_menu.set_status("Could not save the game.", true)


func _on_quit_requested() -> void:
	save_manager.save_now(false)
	get_tree().paused = false
	get_tree().change_scene_to_file(TITLE_SCENE)
