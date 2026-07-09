class_name ENetConnector
extends NetConnector


const DEFAULT_PORT := 8910

var _is_join_intent: bool = false


func _init(net: Node) -> void:
	super(net)
	_net.multiplayer.connected_to_server.connect(_on_connected_to_server)
	_net.multiplayer.connection_failed.connect(_on_connection_failed)


func start_server(id: String, max_clients: int) -> Error:
	var port := _parse_port(id)
	if port <= 0:
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_clients)
	if err != OK:
		return err
	_net.multiplayer.multiplayer_peer = peer
	_net._connector_set_connected(true, false)
	return OK


func start_joining_game(id: String) -> Error:
	var address := id
	var port := DEFAULT_PORT
	if ":" in id:
		var parts := id.split(":")
		address = parts[0]
		if parts.size() > 1:
			port = int(parts[-1])
	if address == "" or port <= 0:
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	_net.multiplayer.multiplayer_peer = peer
	_is_join_intent = true
	return OK


func stop() -> void:
	_is_join_intent = false
	var peer := _net.multiplayer.multiplayer_peer
	if peer:
		peer.close()
	_net.multiplayer.multiplayer_peer = null


func _on_connected_to_server() -> void:
	if _is_join_intent:
		_net._connector_set_connected(false, true)
		_is_join_intent = false


func _on_connection_failed() -> void:
	if _is_join_intent:
		_net._connector_join_failed()
	_is_join_intent = false
	_net._connector_connection_closed()


func _parse_port(id: String) -> int:
	if id == "":
		return DEFAULT_PORT
	if not id.is_valid_int():
		return -1
	return int(id)
