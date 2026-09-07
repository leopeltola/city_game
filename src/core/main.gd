## High-level game state orchestrator handling transitions between Main Menu and Gameplay.
class_name Main
extends Node

static var instance: Main = null

const LOADING_SCREEN_SCENE := preload("res://src/features/main_menu/loading_screen.tscn")
const INGAME_SCENE_PATH := "res://src/core/in_game.tscn"

var _current_ingame_instance: Node = null


func _ready() -> void:
	Main.instance = self

	PlayerManager.player_added.connect(
		func(_pd: PlayerData):
			if _pd.is_local():
				var pname: String = Settings.get_setting("player_name", "Player")
				_pd.set_own_name_to(pname)

			if not Net.is_server:
				return
			if PlayerManager.get_player_count() == 3:
				# Prevent instant execution to let network frames settle
				await get_tree().create_timer(0.3).timeout
				rpc_start_loading.rpc()
	)

	_apply_dev_network_args()


## Cleans up active gameplay nodes and returns to the main menu.
func move_to_main_menu() -> void:
	if is_instance_valid(_current_ingame_instance):
		_current_ingame_instance.queue_free()

	for c in get_children():
		if c != %MainMenu:
			c.queue_free()

	%MainMenu.show()


@rpc("authority", "call_local", "reliable")
func rpc_start_loading() -> void:
	%MainMenu.hide()

	var load_screen := LOADING_SCREEN_SCENE.instantiate()
	add_child(load_screen)

	var packed_scene: PackedScene = await BackgroundLoader.load_resource(
		INGAME_SCENE_PATH,
		load_screen.set_progress,
	)

	var scene_inst := packed_scene.instantiate()
	_current_ingame_instance = scene_inst

	if not Net.is_server:
		# Clients immediately attach the scene to build the NodePath structure
		add_child(scene_inst)
		scene_inst.process_mode = Node.PROCESS_MODE_DISABLED
		load_screen.queue_free()
		ReadyTracker.set_ready("ingame_loaded")
	else:
		# Server holds the instance in memory until clients are ready
		load_screen.queue_free()
		ReadyTracker.set_ready("ingame_loaded")

		await ReadyTracker.everyone_ready
		rpc_finalize_game_start.rpc()


@rpc("authority", "call_local", "reliable")
func rpc_finalize_game_start() -> void:
	if Net.is_server:
		# Server now safely adds the scene after all client paths exist
		ReadyTracker.reset("ingame_loaded")
		add_child(_current_ingame_instance)
	else:
		# Clients now resume or enable processing if it was paused
		if is_instance_valid(_current_ingame_instance):
			_current_ingame_instance.process_mode = PROCESS_MODE_INHERIT


func _apply_dev_network_args() -> void:
	var args := OS.get_cmdline_args()
	if "--block-dev" in args:
		return
	if "--dev-server" in args:
		Net.backend = Net.Backend.ENET
		Net.start_server()
	if "--dev-join" in args:
		Net.backend = Net.Backend.ENET
		Net.start_joining_game("127.0.0.1")
