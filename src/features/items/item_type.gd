class_name ItemType
extends Resource

static var _scene_cache: Dictionary[String, PackedScene] = { }

@export var name: String = "item"
@export var display_name: String = "":
	get:
		return name if display_name.is_empty() else display_name
@export var world_item_path: String = ""
@export var equip_item_path: String = ""
@export var instance_data: Dictionary[StringName, Variant] = { }


## Used by ItemManager to get the data dict
func get_data_dict(id: int = -1) -> Dictionary:
	var ret: Dictionary = {
		"type": name,
		"id": id,
		"position": Vector3.ZERO,
	}
	var inst_data := _get_instance_data_dict()
	return ret.merged(inst_data)


func _get_instance_data_dict() -> Dictionary:
	return instance_data


func get_world_item_scene() -> PackedScene:
	if world_item_path == "":
		return null
	if _scene_cache.has(world_item_path):
		return _scene_cache[world_item_path]
	var scene: PackedScene = load(world_item_path)
	_scene_cache[world_item_path] = scene
	return scene


func get_equip_item_scene() -> PackedScene:
	if equip_item_path == "":
		return null
	if _scene_cache.has(equip_item_path):
		return _scene_cache[equip_item_path]
	var scene: PackedScene = load(equip_item_path)
	_scene_cache[equip_item_path] = scene
	return scene
