class_name ItemSpawner
extends Node3D

@export_enum("Crowbar", "test") var item_type_str: String = "Crowbar"


func _ready() -> void:
	await get_tree().process_frame
	if Net.is_server:
		print("Spawning item")
		var data := ItemManager.create_item_of_type(ItemManager.get_item_type(item_type_str.to_lower()))
		ItemManager.create_world_item_for(data["id"], global_position, global_rotation)
	queue_free()
