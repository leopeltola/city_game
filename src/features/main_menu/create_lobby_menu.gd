extends MarginContainer

signal back_requested

@onready var name_edit: LineEdit = %NameEdit
@onready var create_button: Button = %CreateLobbyButton
@onready var back_button: Button = %BackButton

var _is_hosting: bool = false


func _ready() -> void:
	create_button.pressed.connect(_on_create_pressed)
	back_button.pressed.connect(_on_back_pressed)
	name_edit.text_changed.connect(_on_name_changed)

	Net.server_created.connect(_on_server_created)
	Net.connection_closed.connect(_on_connection_closed)
	SimpleWebRTC.connection_error.connect(_on_connection_error)

	_sync_controls()


func _on_name_changed(_new_text: String) -> void:
	_sync_controls()


func _on_create_pressed() -> void:
	var room_id := name_edit.text.strip_edges()
	if room_id.is_empty():
		return
	var result := Net.start_server(room_id)
	if result != OK:
		ToastOverlay.show_info("Failed to create lobby")
		return
	ToastOverlay.show_info("Creating lobby %s" % room_id)
	_is_hosting = true
	_sync_controls()


func _on_back_pressed() -> void:
	if _is_hosting:
		Net.stop_net()
		_is_hosting = false
		_sync_controls()
	back_requested.emit()


func _on_server_created() -> void:
	ToastOverlay.show_info("Lobby created")


func _on_connection_closed() -> void:
	_is_hosting = false
	_sync_controls()


func _on_connection_error(reason: String) -> void:
	_is_hosting = false
	_sync_controls()
	ToastOverlay.show_info("Network error: %s" % reason)


func _sync_controls() -> void:
	var has_name := not name_edit.text.strip_edges().is_empty()
	name_edit.editable = not _is_hosting
	create_button.disabled = _is_hosting or not has_name
