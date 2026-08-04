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


## Creates an item of given type in the ItemManager and propagates it to everyone
## Returns the just-made item's ID when called on server. Returns nothing on clients.
func create_item_of_type(type_name: StringName) -> Variant:
	if Net.is_server:
		return _rpc_request_create_item(type_name)
	elif Net.is_client:
		_rpc_request_create_item.rpc_id(1, type_name)
	return null


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_create_item(type_name: StringName) -> int:
	assert(Net.is_server)
	var new_id := generate_id()
	var type := get_item_type(type_name)
	var data := type.get_data_dict(new_id)
	_rpc_create_item.rpc(data)
	return new_id


@rpc("any_peer", "call_local", "reliable")
func _rpc_create_item(data: Dictionary) -> void:
	_items[data["id"]] = data


## Creates and returns a WorldItem for given item_id. 
func create_world_item_for(item_id: int, position: Vector3, rotation: Vector3 = Vector3.ZERO) -> void:
	assert(ItemMultiplayerSpawner.instance, "ItemMultiplayerSpawner not present")
	assert(_items.has(item_id))

	if Net.is_server:
		_rpc_create_world_item_for(item_id, position, rotation)
	elif Net.is_client:
		_rpc_create_world_item_for.rpc_id(1, item_id, position, rotation)


@rpc("any_peer", "call_local", "reliable")
func _rpc_create_world_item_for(item_id: int, position: Vector3, rotation: Vector3 = Vector3.ZERO) -> void:
	assert(Net.is_server)
	var data := _items[item_id]
	data["position"] = position
	data["rotation"] = rotation
	ItemMultiplayerSpawner.instance.spawn(data)


## Returns an empty dictionary if item was not found
func get_item_data_dict_by_id(item_id: int) -> Dictionary:
	return _items.get(item_id, { })


## Called by client or server to update the given item's value by key. Atomic operation. 
func set_and_sync_item_data(item_id: int, key: StringName, value: Variant) -> void:
	_rpc_modify_item_data.rpc(item_id, key, value)


@rpc("any_peer", "call_local", "reliable")
func _rpc_modify_item_data(item_id: int, key: StringName, value: Variant) -> void:
	var item_data: Dictionary = _items.get(item_id)
	if not item_data:
		return
	item_data[key] = value


func get_item_types() -> Array[ItemType]:
	return _item_types.values()


func get_item_type(item_type_name: StringName) -> ItemType:
	assert(_item_types.has(item_type_name))
	return _item_types.get(item_type_name)


func generate_id() -> int:
	_id_count += 1
	return _id_count
