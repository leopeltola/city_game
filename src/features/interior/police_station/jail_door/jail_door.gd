class_name JailDoor
extends Node3D
## A jail cell door. Defaults to open and is closed by police when a suspect is put
## inside. A jail key can only OPEN it (never close), and is consumed on use.

@onready var door_handle: Interactable = %DoorHandleInteractableArea
@onready var animation_player: AnimationPlayer = %AnimationPlayer

var is_open := true


func _ready() -> void:
	door_handle.interacted.connect(_on_door_handle_used)
	is_open = true
	door_handle.set_open(true)
	animation_player.play("open")
	animation_player.seek(1.0, true)


func _on_door_handle_used(player_id: int) -> void:
	if is_open:
		return
	_consume_key(player_id)
	# Ask the server to open the door.
	if not is_multiplayer_authority():
		_rpc_request_open.rpc_id(1)
		return

	_open_door()


## Jail keys are single-use: destroys the key the interacting player is holding.
func _consume_key(player_id: int) -> void:
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if player == null or player.inventory == null:
		return
	var equipped := player.get_equipped_item()
	if equipped == null or equipped.item_type == null or equipped.item_type.name != "jail_key":
		return
	player.inventory.remove_item(equipped.item_id)
	ItemManager.destroy_item(equipped.item_id)


@rpc("any_peer", "reliable")
func _rpc_request_open() -> void:
	if not is_multiplayer_authority():
		return
	_open_door()


## Server-side: forces the door to [param open] (police opening/closing it on a suspect).
func set_open(open: bool) -> void:
	if not is_multiplayer_authority() or is_open == open:
		return
	is_open = open
	_rpc_set_door.rpc(is_open)


func _open_door() -> void:
	if is_open:
		return
	is_open = true
	_rpc_set_door.rpc(true)


@rpc("authority", "call_local", "reliable")
func _rpc_set_door(open: bool) -> void:
	is_open = open

	if open:
		animation_player.play("open")
		door_handle.set_open(true)
	else:
		animation_player.play("close")
		door_handle.set_open(false)
