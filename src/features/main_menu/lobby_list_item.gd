extends HBoxContainer

signal join_requested(room_id: String)

@onready var lobby_name_label: Label = %LobbyName
@onready var join_button: Button = %JoinButton

var room_id: String = ""
var display_name: String = ""


func _ready() -> void:
	join_button.pressed.connect(_on_join_pressed)
	_apply_data()


func setup(new_room_id: String, new_display_name: String) -> void:
	room_id = new_room_id
	display_name = new_display_name
	if is_inside_tree():
		_apply_data()


func set_interactable(value: bool) -> void:
	join_button.disabled = not value or room_id.is_empty()


func _apply_data() -> void:
	var name_to_show := display_name
	if name_to_show.is_empty():
		name_to_show = room_id
	lobby_name_label.text = name_to_show
	join_button.disabled = room_id.is_empty()


func _on_join_pressed() -> void:
	if room_id.is_empty():
		return
	join_requested.emit(room_id)
