class_name PlayerData
extends Node

@export var player_name: String
@export var player_id: int
@export var peer_id: int

var color: Color:
	get:
		return [
			Color.DARK_RED,
			Color.DARK_BLUE,
		][-player_id]


func _to_string() -> String:
	return "%s, player_id: %s, peer_id: %s" % [name, player_id, peer_id]


func is_left() -> bool:
	var players: Array[PlayerData] = PlayerManager.get_players()
	for p in players:
		if p.player_id > player_id:
			return true
	return false


func is_right() -> bool:
	return not is_left()


func is_red() -> bool:
	return is_right()


func set_own_name_to(new_name: String) -> void:
	assert(Net.is_client)
	assert(is_local())
	_rpc_set_name.rpc_id(Net.SERVER_ID, new_name)


func is_local() -> bool:
	if Net.is_server:
		return false
	assert(PlayerManager.get_local_player_or_null() != null)
	return PlayerManager.get_local_player_or_null().player_id == player_id


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_name(new_name: String) -> void:
	assert(Net.is_server)
	player_name = new_name
