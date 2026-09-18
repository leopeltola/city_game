extends Node3D



func _ready():
	%FlourBagInteractableArea.interacted.connect(_on_interacted)

func _on_interacted(player_id: int) -> void:
	
	#add_dough_to_inventory(player_id)
	
	spawn_dough()

func spawn_dough() -> void:
	if Net.is_client:
		_rpc_spawn_dough.rpc_id(1)
	elif Net.is_server:
		_rpc_spawn_dough()


@rpc("any_peer", "reliable", "call_remote")
func _rpc_spawn_dough() -> void:
	assert(Net.is_server)
	var id: int = ItemManager.create_item_of_type("dough")
	ItemManager.create_world_item_for(id, %DoughSpawnPos.global_position, %DoughSpawnPos.global_rotation, Vector3.ZERO)






func add_dough_to_inventory(player_id : int) -> void:
	if Net.is_client:
		_rpc_add_dough_to_inventory.rpc_id(1,player_id)
	elif Net.is_server:
		_rpc_add_dough_to_inventory(player_id)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_add_dough_to_inventory(player_id) -> void:
	assert(Net.is_server)
	var id: int = ItemManager.create_item_of_type("dough")
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	var inv := player.inventory as PlayerInventory
	if inv == null or not inv.try_add_item_to_inv(id):
		return # no space in inv, abort
	
