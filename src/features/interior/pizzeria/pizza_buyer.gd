extends Node3D



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

func spawn_cash(amount: int) -> void:
	if Net.is_client:
		_rpc_spawn_cash.rpc_id(1, amount)
	elif Net.is_server:
		_rpc_spawn_cash(amount)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_spawn_cash(amount: int) -> void:
	assert(Net.is_server)
	var remaining: int = amount
	while remaining > 0:
		var bill: int = mini(1000, remaining)
		var id: int = ItemManager.create_item_of_type("cash", { "amount": bill })
		ItemManager.create_world_item_for(id, %CashSpawnPos.global_position, %CashSpawnPos.global_rotation, Vector3.ZERO)
		remaining -= bill
		if remaining > 0:
			await get_tree().create_timer(0.1).timeout
