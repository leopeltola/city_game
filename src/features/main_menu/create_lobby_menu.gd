extends MarginContainer

signal back_requested

@onready var name_edit: LineEdit = %NameEdit
@onready var create_button: Button = %CreateLobbyButton
@onready var back_button: Button = %BackButton

var _is_creating: bool = false


func _ready() -> void:
	create_button.pressed.connect(_on_create_pressed)
	back_button.pressed.connect(_on_back_pressed)
	name_edit.text_changed.connect(_on_name_changed)

	if Lobby.instance:
		Lobby.instance.lobby_failed.connect(_on_lobby_failed)
		Lobby.instance.lobby_joined.connect(_on_lobby_joined)

	_sync_controls()


func _on_name_changed(_new_text: String) -> void:
	_sync_controls()


func _on_create_pressed() -> void:
	var room_id := name_edit.text.strip_edges()
	if room_id.is_empty():
		return

	var result := OK
	if Lobby.instance:
		result = Lobby.instance.create_lobby(room_id)
	if result != OK:
		ToastOverlay.show_info("Failed to create lobby")
		return

	ToastOverlay.show_info("Creating lobby %s" % room_id)
	_is_creating = true
	_sync_controls()


func _on_back_pressed() -> void:
	if _is_creating and Lobby.instance:
		Lobby.instance.leave()
		_is_creating = false
		_sync_controls()
	back_requested.emit()


func _on_lobby_joined() -> void:
	_is_creating = false
	_sync_controls()


func _on_lobby_failed(_reason: String) -> void:
	_is_creating = false
	_sync_controls()


func _sync_controls() -> void:
	var has_name := not name_edit.text.strip_edges().is_empty()
	name_edit.editable = not _is_creating
	create_button.disabled = _is_creating or not has_name
	create_button.text = "Creating..." if _is_creating else "Create"
