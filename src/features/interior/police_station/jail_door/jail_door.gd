extends Node3D

@onready var door_handle: Interactable = %DoorHandleInteractableArea
@onready var animation_player: AnimationPlayer = %AnimationPlayer

var is_open := false
## While locked the handle can't be used. Set by the crime manager during a sentence.
var locked := false


func _ready() -> void:
	door_handle.interacted.connect(_on_door_handle_used)
	door_handle.set_open(false)


func _on_door_handle_used(player_id) -> void:
	# Ask the server to toggle the door.
	if not is_multiplayer_authority():
		_rpc_request_toggle.rpc_id(1)
		return

	_toggle_door()

@rpc("any_peer", "reliable")
func _rpc_request_toggle() -> void:
	if not is_multiplayer_authority():
		return
	_toggle_door()


## Forces the door to a state from the server (used while escorting / jailing). The
## [param lock] flag disables the handle entirely.
func force_set_open(open: bool, lock: bool) -> void:
	if not is_multiplayer_authority():
		return
	locked = lock
	is_open = open
	_rpc_set_door.rpc(is_open, locked)


func _toggle_door() -> void:
	is_open = not is_open
	_rpc_set_door.rpc(is_open, locked)


@rpc("authority", "call_local", "reliable")
func _rpc_set_door(open: bool, lock: bool = false) -> void:
	is_open = open
	locked = lock
	door_handle.locked = lock
	
	if open:
		animation_player.play("open")
		#Door handle tracks state to send correct interaction prompt
		door_handle.set_open(true)
	else:
		animation_player.play_backwards("open")
		door_handle.set_open(false)
