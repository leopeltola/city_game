extends Node

## Emitted when a peer connects to the network session.
signal peer_connected(id: int)
## Emitted when a peer disconnects from the network session.
signal peer_disconnected(id: int)
## Emitted when the local session is closed (server stopped or client disconnected).
signal connection_closed
## Emitted when the server is successfully initialized.
signal server_created
## Emitted when a client fails to connect to a host.
signal join_failed
## Emitted when a client successfully connects to a host.
signal joined_game

const SERVER_ID := 1
const WebRTCConnectorScript := preload("res://src/core/networking/connectors/webrtc_connector.gd")
const ENetConnectorScript := preload("res://src/core/networking/connectors/enet_connector.gd")

enum Backend {
	WEBRTC,
	ENET,
}

var is_server: bool:
	get:
		return multiplayer.is_server() and is_connected
var is_client: bool:
	get:
		return not multiplayer.is_server() and is_connected

@warning_ignore("shadowed_variable_base_class")
var is_connected: bool = false

@export var backend: Backend = Backend.WEBRTC:
	set(val):
		backend = val
		_set_backend(backend)

var _connector: NetConnector


func _ready() -> void:
	multiplayer.peer_connected.connect(func(id): peer_connected.emit(id))
	multiplayer.peer_disconnected.connect(func(id): peer_disconnected.emit(id))
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_set_backend(backend)

#region Lifecycle

## Hosts a lobby at [room_id] with the specified [max_clients].
func start_server(id: String = "", max_clients: int = 32) -> Error:
	assert(not is_connected)
	if is_connected:
		return ERR_ALREADY_IN_USE
	return _connector.start_server(id, max_clients)


## Attempts to join a lobby by [room_id]. This is an async operation.
func start_joining_game(id: String) -> Error:
	assert(not is_connected)
	if is_connected:
		return ERR_ALREADY_IN_USE
	return _connector.start_joining_game(id)


## Closes the current network connection for both clients and servers.
func stop_net() -> void:
	if _connector:
		_connector.stop()
	is_connected = false
	connection_closed.emit()


func server_set_accepting_new_connections(value: bool) -> void:
	if is_server:
		multiplayer.multiplayer_peer.refuse_new_connections = not value

#endregion

#region Internal

func _on_server_disconnected() -> void:
	stop_net()

#endregion

#region Helpers

func get_all_peer_ids() -> Array[int]:
	var peers: Array[int] = []
	if is_connected:
		peers.assign(multiplayer.get_peers())
		peers.append(multiplayer.get_unique_id())
	return peers


func _set_backend(value: Backend) -> void:
	match backend:
		Backend.ENET:
			_connector = ENetConnectorScript.new(self )
			return
		_:
			_connector = WebRTCConnectorScript.new(self )


func _connector_set_connected(emit_server_created: bool, emit_joined_game: bool) -> void:
	is_connected = true
	if emit_server_created:
		server_created.emit()
	if emit_joined_game:
		joined_game.emit()


func _connector_join_failed() -> void:
	join_failed.emit()


func _connector_connection_closed() -> void:
	is_connected = false
	connection_closed.emit()


func _connector_set_idle() -> void:
	is_connected = false

#endregion
