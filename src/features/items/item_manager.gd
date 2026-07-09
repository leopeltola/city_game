extends Node

const _item_types: Dictionary[StringName, ItemType] = {
	"crowbar": preload("res://src/features/items/data/crowbar/crowbar.tres"),
}

var _id_count := 0

## Dictionaries hold the state...
##
## Schema:
## {
##	item_id (int): {
##		"type": StringName,
##		"id": int,
##		"type_var1": Variant,
##		"anothervar": int,
##		"etc": String,
## }
var _items: Dictionary[int, Dictionary] = { }


## Creates an item of given type in the ItemManager WITHOUT spawning it anywhere.
## Returns the just-made item data dict.
## {
##	item_id (int): {
##		"type": StringName,
##		"id": int,
##		"type_var1": Variant,
##		"anothervar": int,
##		"etc": String,
## }
func create_item_of_type(type: ItemType) -> Dictionary:
	var new_id := generate_id()
	var data := type.get_data_dict(new_id)
	_items[new_id] = data
	return data


## Creates and returns a WorldItem for given item_id. 
func create_world_item_for(item_id: int, position: Vector3, rotation: Vector3 = Vector3.ZERO) -> void:
	assert(ItemMultiplayerSpawner.instance, "ItemMultiplayerSpawner not present")
	# TODO replace Node with WorldItem class
	var data := _items[item_id]
	data["position"] = position
	ItemMultiplayerSpawner.instance.spawn(data)


## Returns an empty dictionary if item was not found
func get_item_data_dict_by_id(item_id: int) -> Dictionary:
	return _items.get(item_id, { })


## Called by client or server to update the given item's value by key. Atomic operation. 
func modify_item_data(item_id: int, key: StringName, value: Variant) -> void:
	_rpc_modify_item_data.rpc(item_id, key, value)


func get_item_types() -> Array[ItemType]:
	return _item_types.values()


func get_item_type(item_type_name: StringName) -> ItemType:
	return _item_types.get(item_type_name)


func generate_id() -> int:
	_id_count += 1
	return _id_count


@rpc("any_peer", "call_local", "reliable")
func _rpc_modify_item_data(item_id: int, key: StringName, value: Variant) -> void:
	var item_data: Dictionary = _items.get(item_id)
	if not item_data:
		return
	item_data[key] = value
