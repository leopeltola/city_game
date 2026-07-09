class_name ItemType
extends Resource

@export var name: String = "Item"
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
