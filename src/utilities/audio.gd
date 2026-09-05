extends Node

var sfx_players: Array[AudioStreamPlayer] = []
var sfx_players_3d: Array[AudioStreamPlayer3D] = []
# Music Management
var music_players: Array[AudioStreamPlayer] = []
var _active_music_idx: int = 0
var _music_tween: Tween
# Soundtrack Management
var _soundtrack_queue: Array[AudioStream] = []
var _current_track_index: int = -1
var _is_soundtrack_looping: bool = true


func _ready() -> void:
	_check_cli_mute()

	# SFX Pool
	for i in 15:
		var pl := AudioStreamPlayer.new()
		pl.bus = "Sfx"
		add_child(pl)
		sfx_players.append(pl)

	# 3D SFX Pool
	for i in 15:
		var pl := AudioStreamPlayer3D.new()
		pl.bus = "Sfx"
		add_child(pl)
		sfx_players_3d.append(pl)

	# Dual Music Players for crossfading
	for i in 2:
		var pl := AudioStreamPlayer.new()
		pl.bus = "Music"
		pl.process_mode = Node.PROCESS_MODE_ALWAYS # Keep music during pause
		add_child(pl)
		music_players.append(pl)

func _check_cli_mute() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if "--mute" in args:
		var master_idx := AudioServer.get_bus_index("Master")
		AudioServer.set_bus_mute(master_idx, true)
		AudioServer.set_bus_volume_db(master_idx, -80.0)
		
		get_window().title = get_window().title + " [MUTE]"

func play_sfx(audio_stream: AudioStream, volume_db: float = 0) -> void:
	if not audio_stream:
		return
	var pl := _get_empty_sfx_player()
	if not pl:
		return

	pl.stream = audio_stream
	pl.volume_db = volume_db
	pl.play()


## Play a positional 3D sound at [position] in the world.
func play_sfx_3d(audio_stream: AudioStream, position: Vector3, volume_db: float = 0, max_distance: float = 4000.0) -> void:
	if not audio_stream:
		return
	var pl := _get_empty_sfx_player_3d()
	if not pl:
		return

	pl.stream = audio_stream
	pl.volume_db = volume_db
	pl.max_distance = max_distance
	pl.global_position = position
	pl.play()


## Play a single track with optional crossfade
func play_music(stream: AudioStream, volume_db: float = 0, fade_sec: float = 1.0) -> void:
	if _music_tween:
		_music_tween.kill()

	var old_player = music_players[_active_music_idx]
	_active_music_idx = (_active_music_idx + 1) % 2
	var new_player = music_players[_active_music_idx]

	new_player.stream = stream
	new_player.volume_db = -60 # Start silent
	new_player.play()

	_music_tween = create_tween().set_parallel(true)

	# Fade out old
	_music_tween.tween_property(old_player, "volume_db", -60, fade_sec).set_trans(Tween.TRANS_SINE)
	# Fade in new
	_music_tween.tween_property(new_player, "volume_db", volume_db, fade_sec).set_trans(Tween.TRANS_SINE)

	await _music_tween.finished
	old_player.stop()


## Play a list of tracks in order
func play_soundtrack(streams: Array[AudioStream], loop: bool = true) -> void:
	_soundtrack_queue = streams
	_is_soundtrack_looping = loop
	_current_track_index = 0

	if _soundtrack_queue.is_empty():
		return

	_play_current_soundtrack_item()


func stop_music(fade_sec: float = 1.0) -> void:
	if _music_tween:
		_music_tween.kill()

	_soundtrack_queue.clear()
	var active_player = music_players[_active_music_idx]

	_music_tween = create_tween()
	_music_tween.tween_property(active_player, "volume_db", -60, fade_sec)
	await _music_tween.finished
	active_player.stop()


func _get_empty_sfx_player() -> AudioStreamPlayer:
	for pl in sfx_players:
		if not pl.playing:
			return pl
	return null


func _get_empty_sfx_player_3d() -> AudioStreamPlayer3D:
	for pl in sfx_players_3d:
		if not pl.playing:
			return pl
	return null


func _play_current_soundtrack_item() -> void:
	var track = _soundtrack_queue[_current_track_index]
	await play_music(track, 0, 2.0)

	# Connect to the finished signal of the player currently playing
	var active_player = music_players[_active_music_idx]
	if active_player.finished.is_connected(_on_track_finished):
		active_player.finished.disconnect(_on_track_finished)
	active_player.finished.connect(_on_track_finished, CONNECT_ONE_SHOT)


func _on_track_finished() -> void:
	_current_track_index += 1

	if _current_track_index >= _soundtrack_queue.size():
		if _is_soundtrack_looping:
			_current_track_index = 0
		else:
			return

	_play_current_soundtrack_item()
