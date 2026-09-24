class_name ItemType
extends Resource

static var _scene_cache: Dictionary[String, PackedScene] = { }

@export var name: String = "item"
@export var display_name: String = "":
	get:
		return name if display_name.is_empty() else display_name
@export_file("*.tscn") var world_item_path: String = ""
@export_file("*.tscn") var equip_item_path: String = ""
## Item's visual-only scene. Used by clothing store mannequins
@export var display_scene: PackedScene = null
## Icon shown for this item in slot-based UIs (e.g. the player hotbar).
## Defaults to the engine icon so items missing an icon are easy to spot.
@export var icon: Texture2D = preload("res://icon.svg")
@export var instance_data: Dictionary[StringName, Variant] = { }
## Base monetary value (€) of one of these items. Used to pay off a wanted status
## when police confiscate belongings, and by future systems (shops, fines, ...).
## Cash stacks are worth their instance `money` amount instead.
@export var base_value: int = 0
## Body slot this item wears on (PropSystem.PropSlot). NONE = not a wearable prop.
@export var prop_slot: PropSystem.PropSlot = PropSystem.PropSlot.NONE


## Used by ItemManager to get the data dict.
## [instance_overrides] are merged over the schema defaults; invalid keys are skipped.
func get_data_dict(id: int = -1, instance_overrides: Dictionary = { }) -> Dictionary:
	var ret: Dictionary = {
		"type": name,
		"id": id,
		"position": Vector3.ZERO,
	}
	var inst_data := _get_instance_data_dict().duplicate()
	for key: Variant in instance_overrides:
		if validate_instance_data_key(key, instance_overrides[key]):
			inst_data[StringName(key)] = instance_overrides[key]
	return ret.merged(inst_data)


func _get_instance_data_dict() -> Dictionary:
	return instance_data


## Returns true if [key] is an allowed instance-data key and [value] matches its schema type.
func validate_instance_data_key(key: Variant, value: Variant) -> bool:
	var key_name := StringName(key)
	if not instance_data.has(key_name):
		return false
	return typeof(value) == typeof(instance_data[key_name])


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


func get_display_item_scene() -> PackedScene:
	return display_scene
