extends Node3D

const PlayerScene := preload("res://src/features/player/player.tscn")

func _ready() -> void:
	%MultiplayerSpawner.spawn_function = _spawn_func

	if Net.is_server:
		for p: PlayerData in PlayerManager.get_players():
			_spawn_player(p)
	PlayerManager.player_added.connect(
		func(pd: PlayerData):
			_spawn_player(pd)
	)


func _spawn_player(pd: PlayerData) -> void:
	%MultiplayerSpawner.spawn(pd.player_id)


func _spawn_func(player_id: int):
	var pd := PlayerManager.get_player_by_id(player_id)
	var p: Player = PlayerScene.instantiate()
	p.set_multiplayer_authority(pd.peer_id)
	p.player_id = pd.player_id
	return p
