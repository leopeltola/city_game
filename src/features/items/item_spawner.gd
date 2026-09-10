class_name ItemSpawner
extends Node3D

@export var item_type: ItemType = null


func _ready() -> void:
	await get_tree().process_frame
	if Net.is_server:
		print("Spawning '%s'" % item_type.display_name)
		var id: int = ItemManager.create_item_of_type(item_type.name)
		ItemManager.create_world_item_for(id, global_position, global_rotation)
	queue_free()
