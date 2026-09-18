extends Node3D


func _ready():
	%FridgeInteractableArea.interacted.connect(_on_interacted)

func _on_interacted(player_id: int) -> void:
	spawn_sauce()

func spawn_sauce() -> void:
	if Net.is_client:
		_rpc_spawn_sauce.rpc_id(1)
	elif Net.is_server:
		_rpc_spawn_sauce()


@rpc("any_peer", "reliable", "call_remote")
func _rpc_spawn_sauce() -> void:
	assert(Net.is_server)
	var id: int = ItemManager.create_item_of_type("pizza_sauce")
	ItemManager.create_world_item_for(id, %SauceSpawnPos.global_position, %SauceSpawnPos.global_rotation, Vector3.ZERO)
