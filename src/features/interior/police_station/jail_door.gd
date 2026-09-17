extends Node3D

@onready var door_handle: Interactable = %DoorHandleInteractableArea
@onready var animation_player: AnimationPlayer = %AnimationPlayer

var is_open := false


func _ready() -> void:
	door_handle.interacted.connect(_on_door_handle_used)
	door_handle.prompt = "Open"


func _on_door_handle_used(player_id) -> void:
	# Ask the server to toggle the door.
	if not is_multiplayer_authority():
		_request_toggle.rpc_id(1)
		return

	_toggle_door()

@rpc("any_peer", "reliable")
func _request_toggle() -> void:
	if not is_multiplayer_authority():
		return
	_toggle_door()


func _toggle_door() -> void:
	is_open = not is_open
	_set_door.rpc(is_open)


@rpc("authority", "call_local", "reliable")
func _set_door(open: bool) -> void:
	is_open = open
	
	if open:
		animation_player.play("open")
		door_handle.prompt = "Close"
	else:
		animation_player.play_backwards("open")
		door_handle.prompt = "Open"
