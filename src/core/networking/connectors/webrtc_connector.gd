class_name WebRTCConnector
extends NetConnector


const DEFAULT_ROOM_ID := "default"
const SIGNALING_SERVER_URL := "wss://simplewebrtc.pelto.dev/v2/ws"
const GAME_ID := "peltodev-multiplayer-template"
const WEBRTC_TOPOLOGY := SimpleWebRTC.Topology.SERVER_AUTHORITATIVE

var _is_join_intent: bool = false
var _is_host_intent: bool = false
var _room_id: String = DEFAULT_ROOM_ID


func _init(net: Node) -> void:
	super(net)
	_apply_webrtc_defaults()
	SimpleWebRTC.signaling_connected.connect(_on_signaling_connected)
	SimpleWebRTC.match_ready.connect(_on_match_ready)
	SimpleWebRTC.room_closed.connect(_on_room_closed)
	SimpleWebRTC.connection_error.connect(_on_connection_error)
	SimpleWebRTC.state_changed.connect(_on_state_changed)


func start_server(id: String, max_clients: int) -> Error:
	_apply_webrtc_defaults()
	_is_host_intent = true
	_is_join_intent = false
	_room_id = id if id != "" else DEFAULT_ROOM_ID
	SimpleWebRTC.host_lobby(_room_id, WEBRTC_TOPOLOGY, max_clients)
	return OK


func start_joining_game(id: String) -> Error:
	_apply_webrtc_defaults()
	_is_host_intent = false
	_is_join_intent = true
	_room_id = id if id != "" else DEFAULT_ROOM_ID
	SimpleWebRTC.join_lobby(_room_id, WEBRTC_TOPOLOGY)
	return OK


func stop() -> void:
	SimpleWebRTC.leave()
	_is_join_intent = false
	_is_host_intent = false


func _on_signaling_connected(_peer_id: int) -> void:
	_net._connector_set_connected(_net.multiplayer.is_server(), _is_join_intent)


func _on_match_ready() -> void:
	if _is_host_intent and not _net.multiplayer.is_server():
		_net._connector_set_connected(true, false)


func _on_room_closed() -> void:
	_is_join_intent = false
	_is_host_intent = false
	_net._connector_connection_closed()


func _on_connection_error(_reason: String) -> void:
	if _is_join_intent:
		_net._connector_join_failed()
	_is_join_intent = false
	_is_host_intent = false
	_net._connector_connection_closed()


func _on_state_changed(new_state: int) -> void:
	if new_state == SimpleWebRTC.State.IDLE:
		_is_join_intent = false
		_is_host_intent = false
		_net._connector_set_idle()


func _apply_webrtc_defaults() -> void:
	SimpleWebRTC.signaling_server_url = SIGNALING_SERVER_URL
	SimpleWebRTC.game_id = GAME_ID
