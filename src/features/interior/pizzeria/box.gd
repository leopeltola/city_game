extends Node3D


func _ready():
	%BoxInteractableArea.interacted.connect(_on_interacted)

func _on_interacted(player_id: int) -> void:
	spawn_box()

func spawn_box() -> void:
	if Net.is_client:
		_rpc_spawn_box.rpc_id(1)
	elif Net.is_server:
		_rpc_spawn_box()


@rpc("any_peer", "reliable", "call_remote")
func _rpc_spawn_box() -> void:
	assert(Net.is_server)
	var id: int = ItemManager.create_item_of_type("pizza_box")
	ItemManager.create_world_item_for(id, %BoxSpawnPos.global_position, %BoxSpawnPos.global_rotation, Vector3.ZERO)
