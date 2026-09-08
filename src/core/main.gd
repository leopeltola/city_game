class_name Main
extends Node

static var instance: Main = null

const LOADING_SCREEN_SCENE := preload("res://src/features/main_menu/loading_screen.tscn")
const INGAME_SCENE_PATH := "res://src/core/in_game.tscn"

var _current_ingame_instance: Node = null
var _loading_started := false

const MIN_CLIENTS_TO_START := 2


func _ready() -> void:
	Main.instance = self
	_apply_window_args()

	PlayerManager.player_added.connect(
		func(pd: PlayerData):
			if pd.is_local():
				var pname: String = Settings.get_setting("player_name", "Player")
				pd.set_own_name_to(pname)

			if not Net.is_server:
				return
			print("Players: %s" % PlayerManager.get_player_count())
			if PlayerManager.get_player_count() >= MIN_CLIENTS_TO_START and not _loading_started:
				_loading_started = true
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
		add_child(scene_inst)
		scene_inst.process_mode = Node.PROCESS_MODE_DISABLED
		load_screen.queue_free()
		ReadyTracker.set_ready("ingame_loaded")
	else:
		load_screen.queue_free()
		ReadyTracker.set_ready("ingame_loaded")

		while not ReadyTracker.is_event_complete("ingame_loaded"):
			await get_tree().process_frame
		rpc_finalize_game_start.rpc()


@rpc("authority", "call_local", "reliable")
func rpc_finalize_game_start() -> void:
	if Net.is_server:
		if not is_instance_valid(_current_ingame_instance) or _current_ingame_instance.is_inside_tree():
			return
		ReadyTracker.reset("ingame_loaded")
		add_child(_current_ingame_instance)
	else:
		if is_instance_valid(_current_ingame_instance) \
				and _current_ingame_instance.process_mode == PROCESS_MODE_DISABLED:
			_current_ingame_instance.process_mode = PROCESS_MODE_INHERIT


## Parses and applies window sizing and screen placement from CLI arguments.
## Accounts for OS window decorations to prevent the title bar from rendering off-screen.
func _apply_window_args() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	var window := get_window()
	var target_screen := window.current_screen
	print(args)
	# 1. Parse target screen
	for i in range(args.size()):
		if args[i] == "--move-screen" and i + 1 < args.size() and args[i + 1].is_valid_int():
			target_screen = clampi(args[i + 1].to_int() - 1, 0, DisplayServer.get_screen_count() - 1)
			print("Target screen: ", target_screen)
			break

	if window.current_screen != target_screen:
		window.current_screen = target_screen
		# Yield two frames to ensure the OS window manager context switches fully
		await get_tree().process_frame
		await get_tree().process_frame

	var usable_rect := DisplayServer.screen_get_usable_rect(window.current_screen)

	# 2. Handle simple maximization
	if "--screen-maximized" in args:
		window.mode = Window.MODE_MAXIMIZED
		return

	# 3. Handle split-screen snapping
	var is_left := "--screen-left" in args
	var is_right := "--screen-right" in args

	if is_left or is_right:
		window.mode = Window.MODE_WINDOWED

		# Calculate OS decoration metrics (title bar height, border width)
		var decor_offset := window.position - DisplayServer.window_get_position_with_decorations()
		var decor_size := DisplayServer.window_get_size_with_decorations() - window.size

		# Calculate target dimensions, subtracting the borders so the window fits exactly
		var target_w := (usable_rect.size.x / 2) - decor_size.x
		var target_h := usable_rect.size.y - decor_size.y
		window.size = Vector2i(target_w, target_h)

		# Calculate target X/Y and offset by the decoration margin
		var target_x := usable_rect.position.x
		if is_right:
			target_x += usable_rect.size.x / 2

		window.position = Vector2i(target_x, usable_rect.position.y) + decor_offset

	elif window.current_screen != target_screen:
		# Center the window if it was moved to a new screen without split arguments
		window.move_to_center()


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
