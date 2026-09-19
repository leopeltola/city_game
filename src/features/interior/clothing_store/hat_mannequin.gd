extends Node3D

@export var shown_item: ItemType
@export var price : int = 100





func _ready():
	%MannequinInteractableArea.interacted.connect(_on_interacted)
	if shown_item:
		var item_instance = shown_item.get_display_item_scene().instantiate()
		%HatContainer.add_child(item_instance)

func _on_interacted(player_id : int) -> void:
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if not player:
		return
	var item := player.get_equipped_item()
	if item and item.item_type and item.item_type.name == "cash":
		var item_id = item.item_id
		var total_amount : int = ItemManager.get_item_data(item_id, "amount", 0)
		var remaining := total_amount - price
		if remaining <= 0:
			(player.inventory as PlayerInventory).pop_active_item()
			ItemManager.destroy_item(item_id)
		else:
			ItemManager.set_and_sync_item_data(item_id, "amount", remaining)
		
		spawn_item()

func get_price():
	return price


func spawn_item() -> void:
	if Net.is_client:
		_rpc_spawn_item.rpc_id(1)
	elif Net.is_server:
		_rpc_spawn_item()


@rpc("any_peer", "reliable", "call_remote")
func _rpc_spawn_item() -> void:
	assert(Net.is_server)
	var item_name = shown_item.name
	var id: int = ItemManager.create_item_of_type(item_name)
	ItemManager.create_world_item_for(id, %ItemSpawnPos.global_position, %ItemSpawnPos.global_rotation, Vector3.ZERO)
