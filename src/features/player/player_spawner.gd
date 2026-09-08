extends Node3D

const PlayerScene := preload("res://src/features/player/player.tscn")

func _ready() -> void:
	%MultiplayerSpawner.spawn_function = _spawn_func

	PlayerManager.player_added.connect(
		func(pd: PlayerData):
			if Net.is_server:
				_spawn_player(pd)
	)

	if Net.is_server:
		# Defer one frame so clients have processed rpc_finalize_game_start and
		# resumed processing before player spawn RPCs are sent. Spawning in the
		# same frame as finalize can reach clients while their scene is still
		# PROCESS_MODE_DISABLED, causing the spawn to be dropped. This mirrors
		# the ItemSpawner timing, which reliably replicates.
		await get_tree().process_frame
		for p: PlayerData in PlayerManager.get_players():
			_spawn_player(p)


func _spawn_player(pd: PlayerData) -> void:
	if PlayerManager.get_player_node_by_id(pd.player_id) != null:
		return
	%MultiplayerSpawner.spawn(pd.player_id)


func _spawn_func(player_id: int):
	var pd := PlayerManager.get_player_by_id(player_id)
	if pd == null:
		push_error("PlayerSpawner: no PlayerData found for player_id %s" % player_id)
		return null
	var p: Player = PlayerScene.instantiate()
	p.set_multiplayer_authority(pd.peer_id)
	p.player_id = player_id
	return p
