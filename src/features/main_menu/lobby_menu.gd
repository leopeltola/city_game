extends MarginContainer

const LobbyListItemScene := preload("res://src/features/main_menu/lobby_list_item.tscn")

signal back_requested

@onready var lobby_list: VBoxContainer = %LobbyList
@onready var back_button: Button = $MarginContainer/VBoxContainer/Button

var _is_joining: bool = false


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	visibility_changed.connect(_on_visibility_changed)

	SimpleWebRTC.lobby_list_received.connect(_on_lobby_list_received)
	SimpleWebRTC.lobby_snapshot_received.connect(_on_lobby_list_received)
	SimpleWebRTC.lobby_error.connect(_on_lobby_error)
	SimpleWebRTC.lobby_feed_connected.connect(_on_lobby_feed_connected)
	SimpleWebRTC.connection_error.connect(_on_connection_error)

	Net.join_failed.connect(_on_join_failed)
	Net.connection_closed.connect(_on_connection_closed)
	Net.joined_game.connect(_on_joined_game)

	if is_visible_in_tree():
		_on_visibility_changed()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_set_joining(false)
		_clear_lobby_list()
		_prepare_lobby_feed()
		if SimpleWebRTC.get_lobbies().size() > 0:
			_rebuild_lobby_list(SimpleWebRTC.get_lobbies())
	else:
		SimpleWebRTC.unsubscribe_lobbies()
		SimpleWebRTC.disconnect_lobby_feed()


func _on_back_pressed() -> void:
	if _is_joining:
		Net.stop_net()
		_set_joining(false)
	back_requested.emit()


func _on_lobby_list_received(lobbies: Array[Dictionary]) -> void:
	_rebuild_lobby_list(lobbies)


func _on_lobby_error(reason: String) -> void:
	ToastOverlay.show_info("Lobby error: %s" % reason)


func _on_lobby_feed_connected() -> void:
	if is_visible_in_tree():
		SimpleWebRTC.refresh_lobby_list()


func _on_connection_error(reason: String) -> void:
	_set_joining(false)
	ToastOverlay.show_info("Network error: %s" % reason)


func _on_join_failed() -> void:
	_set_joining(false)
	ToastOverlay.show_info("Failed to join lobby")


func _on_connection_closed() -> void:
	_set_joining(false)


func _on_joined_game() -> void:
	ToastOverlay.show_info("Joined lobby")


func _rebuild_lobby_list(lobbies: Array[Dictionary]) -> void:
	_clear_lobby_list()

	for lobby: Dictionary in lobbies:
		var room_id := _get_room_id(lobby)
		if room_id.is_empty():
			continue
		var display_name := _get_lobby_name(lobby, room_id)
		var item := LobbyListItemScene.instantiate()
		lobby_list.add_child(item)
		item.setup(room_id, display_name)
		item.join_requested.connect(_on_join_requested)
		item.set_interactable(not _is_joining)


func _clear_lobby_list() -> void:
	for child in lobby_list.get_children():
		child.queue_free()


func _on_join_requested(room_id: String) -> void:
	if _is_joining:
		return
	var result := Net.start_joining_game(room_id)
	if result != OK:
		ToastOverlay.show_info("Failed to start join")
		return
	ToastOverlay.show_info("Joining lobby %s" % room_id)
	_set_joining(true)


func _set_joining(value: bool) -> void:
	_is_joining = value
	back_button.disabled = value
	for child in lobby_list.get_children():
		if child.has_method("set_interactable"):
			child.set_interactable(not value)


func _get_room_id(lobby: Dictionary) -> String:
	if lobby.has("room_id"):
		return str(lobby.get("room_id", "")).strip_edges()
	if lobby.has("roomId"):
		return str(lobby.get("roomId", "")).strip_edges()
	if lobby.has("room"):
		return str(lobby.get("room", "")).strip_edges()
	if lobby.has("id"):
		return str(lobby.get("id", "")).strip_edges()
	return ""


func _get_lobby_name(lobby: Dictionary, room_id: String) -> String:
	if lobby.has("name"):
		return str(lobby.get("name", "")).strip_edges()
	if lobby.has("room_name"):
		return str(lobby.get("room_name", "")).strip_edges()
	if lobby.has("roomName"):
		return str(lobby.get("roomName", "")).strip_edges()
	return room_id


func _prepare_lobby_feed() -> void:
	assert(Net.backend == Net.Backend.WEBRTC)
	SimpleWebRTC.signaling_server_url = WebRTCConnector.SIGNALING_SERVER_URL
	SimpleWebRTC.game_id = WebRTCConnector.GAME_ID
	SimpleWebRTC.disconnect_lobby_feed()
	var connect_error: Error = SimpleWebRTC.connect_lobby_feed()
	if connect_error != OK:
		ToastOverlay.show_info("Lobby feed failed: %s" % error_string(connect_error))
		return
	SimpleWebRTC.subscribe_lobbies()
