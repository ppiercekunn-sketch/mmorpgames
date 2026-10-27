extends Node2D
## Integration scene: assembles world, player, enemies, progression and UI.
## Each system only knows the contracts in docs/ARCHITECTURE.md; this script
## is the one place that wires them together.

const ZONE_SCENE := preload("res://world/zone.tscn")
const PLAYER_SCENE := preload("res://combat/player/player.tscn")
const COMBAT_HUD_SCENE := preload("res://combat/ui/combat_hud.tscn")
const PROGRESSION_UI_SCENE := preload("res://progression/ui/progression_ui.tscn")

var zone: Zone
var player: Player
var camera: FollowCamera
var enemy_spawner: EnemySpawner
var progression: Progression


func _ready() -> void:
	zone = ZONE_SCENE.instantiate()
	add_child(zone)
	Events.zone_loaded.emit("field_1")

	var entities := zone.get_entities_root()
	player = PLAYER_SCENE.instantiate()
	player.display_name = str(Session.character.get("name", "Wanderer"))
	player.global_position = zone.get_player_spawn()
	entities.add_child(player)
	Events.player_spawned.emit(player)

	camera = FollowCamera.new()
	add_child(camera)
	camera.follow(player)

	enemy_spawner = EnemySpawner.new()
	add_child(enemy_spawner)
	enemy_spawner.setup(entities)

	progression = Progression.new()
	add_child(progression)
	progression.setup(player, entities)

	add_child(COMBAT_HUD_SCENE.instantiate())
	add_child(PROGRESSION_UI_SCENE.instantiate())
