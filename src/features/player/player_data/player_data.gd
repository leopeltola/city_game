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
	return "(%s, player_id: %s, peer_id: %s, is_local: %s)" % [name, player_id, peer_id, is_local()]


func set_own_name_to(new_name: String) -> void:
	assert(Net.is_client)
	assert(is_local())
	_rpc_set_name.rpc_id(Net.SERVER_ID, new_name)


func is_local() -> bool:
	if Net.is_server:
		return false
	return multiplayer.get_unique_id() == peer_id


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_name(new_name: String) -> void:
	assert(Net.is_server)
	player_name = new_name
