extends Node

## Emitted on clients when a new message is received.
signal message_received(message: Dictionary)

## Schema: {
##     player_id(int): Array[Message Dictionary]
## }
## On server hold everyone's messages, on clients only theirs.
var message_data: Dictionary[int, Array] = { }


## Sends a message to a specific player ID.
func send_message_to(receiving_player_id: int, sender: String, title: String, msg: String) -> void:
	if Net.is_server:
		_rpc_send_message_to(receiving_player_id, sender, title, msg)
	elif Net.is_client:
		_rpc_send_message_to.rpc_id(1, receiving_player_id, sender, title, msg)


## Returns all messages for the local player on clients.
func get_local_messages() -> Array[Dictionary]:
	if Net.is_server or message_data.is_empty():
		return []
	var local_messages: Array[Dictionary] = []
	local_messages.assign(message_data.values()[0])
	return local_messages


## Returns all stored messages for a specific player ID.
func get_messages_for_player(player_id: int) -> Array[Dictionary]:
	if not message_data.has(player_id):
		return []
	var messages: Array[Dictionary] = []
	messages.assign(message_data[player_id])
	return messages


@rpc("any_peer", "call_remote", "reliable")
func _rpc_send_message_to(receiving_player_id: int, sender: String, title: String, msg: String) -> void:
	assert(Net.is_server)
	var message: Dictionary = {
		"sender": sender,
		"title": title,
		"msg": msg,
	}
	_store_message(receiving_player_id, message)

	var pd: PlayerData = PlayerManager.get_player_by_id(receiving_player_id)
	if pd:
		_rpc_receive_message.rpc_id(pd.peer_id, receiving_player_id, message)


@rpc("authority", "call_remote", "reliable")
func _rpc_receive_message(receiving_player_id: int, message: Dictionary) -> void:
	assert(Net.is_client)
	_store_message(receiving_player_id, message)
	message_received.emit(message)


func _store_message(player_id: int, message: Dictionary) -> void:
	if not message_data.has(player_id):
		var list: Array[Dictionary] = []
		message_data[player_id] = list
	message_data[player_id].append(message)
