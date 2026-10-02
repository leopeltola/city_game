extends Node3D

const CASH_SFX: AudioStream = preload("res://assets/sfx/slot_machine/cash_register.ogg")


func _ready():
	%BuyerInteractableArea.interacted.connect(_on_interacted)

func _on_interacted(player_id: int) -> void:
	# create equip item for it
	var p: Player = PlayerManager.get_local_player_node_or_null()
	var inv := p.inventory as PlayerInventory
	var item := p.get_equipped_item()
	var item_id : int = item.item_id
	var is_carrying_pizza_box: bool = item and item.item_type and item.item_type.name == "pizza_box"
	var is_empty: bool = ItemManager.get_item_data(item_id, &"is_empty") == true
	
	if not is_carrying_pizza_box or is_empty:
		return
	
	var destroyed_item_id := inv.pop_active_item()
	ItemManager.destroy_item(destroyed_item_id)
	
	spawn_cash(100)
	Audio.play_sfx_3d(CASH_SFX, global_position, -6.0, 25.0, true)

func spawn_cash(amount: int) -> void:
	if Net.is_client:
		_rpc_spawn_cash.rpc_id(1, amount)
	elif Net.is_server:
		_rpc_spawn_cash(amount)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_spawn_cash(amount: int) -> void:
	assert(Net.is_server)
	await MoneyManager.spawn_cash_stacks(
		amount,
		%CashSpawnPos.global_position,
		%CashSpawnPos.global_rotation,
	)
