extends Node3D

@export var owner_id: int
@export var door_handle: Node3D
@export var door_lock: Node3D

var price: int = 50000

var is_open = false
var locked = false

@onready var animation_player = %AnimationPlayer


func _ready():
	door_handle.interacted.connect(_on_interacted)
	door_lock.interacted.connect(_on_lock_used)


func get_owner_id():
	return owner_id


func get_price():
	return price


func _on_interacted(player_id: int) -> void:
	var player: Player = PlayerManager.get_player_node_by_id(player_id)

	var item: ItemEquip = player.get_equipped_item()

	if owner_id > 0 and not locked:
		_rpc_request_open.rpc_id(1)
	elif owner_id < 0:
		if item and item.item_type and item.item_type.instance_data.has("money"):
			var item_id = item.item_id
			var total_amount: int = ItemManager.get_item_data(item_id, "money", 0)
			var remaining := total_amount - price
			if remaining <= 0:
				(player.inventory as PlayerInventory).pop_active_item()
				ItemManager.destroy_item(item_id)
			else:
				ItemManager.set_and_sync_item_data(item_id, "money", remaining)
			_rpc_request_claim.rpc_id(1, player_id)


func _on_lock_used(player_id: int) -> void:
	_rpc_request_lock.rpc_id(1)


@rpc("any_peer", "reliable", "call_local")
func _rpc_request_lock():
	if locked:
		_rpc_sync_lock.rpc(false)
	else:
		_rpc_sync_lock.rpc(true)


@rpc("authority", "reliable", "call_local")
func _rpc_sync_lock(new_state):
	locked = new_state


@rpc("any_peer", "reliable")
func _rpc_request_claim(claimer_id):
	if owner_id < 0:
		_rpc_sync_claim.rpc(claimer_id)


@rpc("authority", "reliable", "call_local")
func _rpc_sync_claim(claimer_id):
	owner_id = claimer_id
	if door_handle:
		door_handle.claimed = true
		door_lock.claimed = true
	else:
		push_error("Dorm door didn't find door handle! Multiplayer id: ", multiplayer.get_unique_id())


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
		_rpc_set_door.rpc(false)
		is_open = false
	else:
		_rpc_set_door.rpc(true)
		is_open = true


@rpc("authority", "call_local", "reliable")
func _rpc_set_door(open: bool) -> void:
	is_open = open

	if open:
		animation_player.play("open")
		door_handle.set_open(true)
	else:
		animation_player.play_backwards("open")
		door_handle.set_open(false)
