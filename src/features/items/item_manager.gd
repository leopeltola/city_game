extends Node

const _item_types: Dictionary[StringName, ItemType] = {
	"bat": preload("res://src/features/items/data/bat/bat.tres"),
	"cash": preload("res://src/features/items/data/cash/cash.tres"),
	"bottle_crate": preload("res://src/features/items/data/bottle_crate/bottle_crate.tres"),
	"photo": preload("res://src/features/items/data/photo/photo.tres"),
	"fedora": preload("res://src/features/items/data/fedora/fedora.tres"),
	"watch": preload("res://src/features/items/data/watch/watch.tres"),
	"police_hat": preload("res://src/features/items/data/police_hat/police_hat.tres"),
	"police_body": preload("res://src/features/items/data/police_body/police_body.tres"),
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


## Creates an item of given type in the ItemManager and propagates it to everyone.
## [instance_data] is merged over the type's schema defaults for this specific item.
## Returns the just-made item's ID when called on server. Returns nothing on clients.
func create_item_of_type(type_name: StringName, instance_data: Dictionary = { }) -> Variant:
	if Net.is_server:
		return _rpc_request_create_item(type_name, instance_data)
	elif Net.is_client:
		_rpc_request_create_item.rpc_id(1, type_name, instance_data)
	return null


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_create_item(type_name: StringName, instance_data: Dictionary = { }) -> int:
	assert(Net.is_server)
	var new_id := generate_id()
	var type := get_item_type(type_name)
	var data := type.get_data_dict(new_id, instance_data)
	_rpc_create_item.rpc(data)
	return new_id


@rpc("any_peer", "call_local", "reliable")
func _rpc_create_item(data: Dictionary) -> void:
	_items[data["id"]] = data


## Creates and returns a WorldItem for given item_id. 
## [force] is an optional initial impulse (Vector3) applied once on spawn to fly the item.
func create_world_item_for(item_id: int, position: Vector3, rotation: Vector3 = Vector3.ZERO, force: Vector3 = Vector3.ZERO, owner_player_id: int = 0) -> void:
	assert(ItemMultiplayerSpawner.instance, "ItemMultiplayerSpawner not present")
	assert(_items.has(item_id))

	if Net.is_server:
		_rpc_create_world_item_for(item_id, position, rotation, force, owner_player_id)
	elif Net.is_client:
		_rpc_create_world_item_for.rpc_id(1, item_id, position, rotation, force, owner_player_id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_create_world_item_for(item_id: int, position: Vector3, rotation: Vector3 = Vector3.ZERO, force: Vector3 = Vector3.ZERO, owner_player_id: int = 0) -> void:
	assert(Net.is_server)
	var data := _items[item_id]
	data["position"] = position
	data["rotation"] = rotation
	data["launch_force"] = force
	if owner_player_id:
		data["owner"] = owner_player_id # player id, 0 = none
	ItemMultiplayerSpawner.instance.spawn(data)


## Destroys the given item's data. Call from client or server; the server applies it to all peers.
func destroy_item(item_id: int) -> void:
	if Net.is_server:
		_rpc_request_destroy_item(item_id)
	elif Net.is_client:
		_rpc_request_destroy_item.rpc_id(1, item_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_destroy_item(item_id: int) -> void:
	assert(Net.is_server)
	if not _items.has(item_id):
		return
	_rpc_apply_destroy_item.rpc(item_id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_apply_destroy_item(item_id: int) -> void:
	_items.erase(item_id)


## Returns the live replicated data dictionary for the given item.
## READ-ONLY: do not mutate, or you will desync peers. Use get_item_data() for safe reads.
## Returns an empty dictionary if the item was not found.
func get_item_data_dict_raw(item_id: int) -> Dictionary:
	return _items.get(item_id, { })


## Safe single-key read of an item's instance data. Returns [default] if the item or key is missing.
func get_item_data(item_id: int, key: StringName, default: Variant = null) -> Variant:
	return get_item_data_dict_raw(item_id).get(key, default)


## Called by client or server to request an update of the given item's value by key.
## Applied only on the server (authority) after schema validation, then synced to all peers.
func set_and_sync_item_data(item_id: int, key: StringName, value: Variant) -> void:
	if Net.is_server:
		_rpc_request_modify_item_data(item_id, key, value)
	elif Net.is_client:
		_rpc_request_modify_item_data.rpc_id(1, item_id, key, value)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_modify_item_data(item_id: int, key: StringName, value: Variant) -> void:
	assert(Net.is_server)
	var item_data: Dictionary = _items.get(item_id)
	if not item_data:
		return
	var type: ItemType = get_item_type(item_data["type"])
	if not type.validate_instance_data_key(key, value):
		return
	_rpc_apply_item_data.rpc(item_id, key, value)


@rpc("any_peer", "call_local", "reliable")
func _rpc_apply_item_data(item_id: int, key: StringName, value: Variant) -> void:
	var item_data: Dictionary = _items.get(item_id)
	if not item_data:
		return
	item_data[key] = value


func get_item_types() -> Array[ItemType]:
	return _item_types.values()


func get_item_type(item_type_name: StringName) -> ItemType:
	assert(_item_types.has(item_type_name), "Item %s not found in item type registry" % item_type_name)
	return _item_types.get(item_type_name)


func generate_id() -> int:
	_id_count += 1
	return _id_count
