extends Node3D




func _ready():
	%TableInteractableArea.interacted.connect(_on_interacted)




func _on_interacted(player_id: int) -> void:
	# create equip item for it
	var p: Player = PlayerManager.get_local_player_node_or_null()
	var inv := p.inventory as PlayerInventory
	var item := p.get_equipped_item()
	
	
	var destroyed_item_id := inv.pop_active_item()
	ItemManager.destroy_item(destroyed_item_id)
	
	spawn_pizza()

func spawn_pizza() -> void:
	if Net.is_client:
		_rpc_spawn_pizza.rpc_id(1)
	elif Net.is_server:
		_rpc_spawn_pizza()


@rpc("any_peer", "reliable", "call_remote")
func _rpc_spawn_pizza() -> void:
	assert(Net.is_server)
	var id: int = ItemManager.create_item_of_type("pizza")
	ItemManager.create_world_item_for(id, %PizzaSpawnPos.global_position, %PizzaSpawnPos.global_rotation, Vector3.ZERO)
	
