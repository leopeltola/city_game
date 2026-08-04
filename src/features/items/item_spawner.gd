class_name ItemSpawner
extends Node3D

@export_enum("crowbar") var item_type_str: String = "crowbar"


func _ready() -> void:
	await get_tree().process_frame
	if Net.is_server:
		print("Spawning item")
		var id: int = ItemManager.create_item_of_type(item_type_str)
		print(id)
		ItemManager.create_world_item_for(id, global_position, global_rotation)
	queue_free()
