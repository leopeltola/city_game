extends Node
## Manages global item lifecycles, instance state, and network synchronization
## across peers.
## 
## State mutations, deletions, and world spawning are server-authoritative.
## Calls executed on the server take effect immediately; calls originating
## from clients are deferred until validated and synchronized by the server.
## [br][br]
## Uses peer-partitioned 64-bit identifiers to allow immediate, collision-free
## local allocation without server round-trips.


const _item_types: Dictionary[StringName, ItemType] = {
	"rect_shades": preload("res://src/features/items/data/rect_shades/rect_shades.tres"),
	"wilzu_hair": preload("res://src/features/items/data/wilzu_hair/wilzu_hair.tres"),
	"tank_top": preload("res://src/features/items/data/tank_top/tank_top.tres"),
	"open_shirt": preload("res://src/features/items/data/open_shirt/open_shirt.tres"),
	"guard_hat": preload("res://src/features/items/data/guard_hat/guard_hat.tres"),
	"guard_body": preload("res://src/features/items/data/guard_body/guard_body.tres"),
	"moustache": preload("res://src/features/items/data/moustache/moustache.tres"),
	"rect_glasses": preload("res://src/features/items/data/rect_glasses/rect_glasses.tres"),
	"suit": preload("res://src/features/items/data/suit/suit.tres"),
	"aviator_glasses": preload("res://src/features/items/data/aviator_glasses/aviator_glasses.tres"),
	"cap": preload("res://src/features/items/data/cap/cap.tres"),
	"bat": preload("res://src/features/items/data/bat/bat.tres"),
	"cash": preload("res://src/features/items/data/cash/cash.tres"),
	"bottle_crate": preload("res://src/features/items/data/bottle_crate/bottle_crate.tres"),
	"photo": preload("res://src/features/items/data/photo/photo.tres"),
	"fedora": preload("res://src/features/items/data/fedora/fedora.tres"),
	"watch": preload("res://src/features/items/data/watch/watch.tres"),
	"jail_key": preload("res://src/features/items/data/jail_key/jail_key.tres"),
	"police_hat": preload("res://src/features/items/data/police_hat/police_hat.tres"),
	"police_body": preload("res://src/features/items/data/police_body/police_body.tres"),
	"dough": preload("res://src/features/items/data/pizza/dough/dough.tres"),
	"pizza": preload("res://src/features/items/data/pizza/pizza/pizza.tres"),
	"pizza_box": preload("res://src/features/items/data/pizza/pizza_box/pizza_box.tres"),
	"pizza_sauce": preload("res://src/features/items/data/pizza/pizza_sauce/pizza_sauce.tres"),
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


## Creates an item of [param type_name] and replicates it across all peers.
## [br][br]
## Merges [param instance_data] over the type's schema defaults. Generates a globally 
## unique item ID partitioned by peer, registered locally before this function returns.
## [br][br]
## Can be called on both server and client. Returned item ID can be used locally immediately. 
func create_item_of_type(type_name: StringName, instance_data: Dictionary = { }) -> int:
	var new_id := generate_id()
	var data := get_item_type(type_name).get_data_dict(new_id, instance_data)
	_items[new_id] = data

	if Net.is_server:
		_rpc_create_item.rpc(data)
	elif Net.is_client:
		_rpc_request_create_item.rpc_id(1, new_id, type_name, instance_data)

	return new_id


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_create_item(item_id: int, type_name: StringName, instance_data: Dictionary = { }) -> void:
	assert(Net.is_server)
	if not _item_types.has(type_name):
		return
	_execute_create_item(item_id, type_name, instance_data)


# Server-side application of a create request: stores the item and syncs it to all peers.
func _execute_create_item(item_id: int, type_name: StringName, instance_data: Dictionary) -> void:
	var data := get_item_type(type_name).get_data_dict(item_id, instance_data)
	_items[item_id] = data
	_rpc_create_item.rpc(data)


@rpc("authority", "call_remote", "reliable")
func _rpc_create_item(data: Dictionary) -> void:
	_items[data["id"]] = data


## Creates and returns a WorldItem for given item_id. 
## [br][br]
## [param force] can be used to send the item flying immediately. 
## [br][br]
## Can be called on both server and client. When called on client, execution is delayed. 
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


## Destroys the given item's data. 
## [br][br]
## Can be called on both server and client. When called on client, execution is delayed. 
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


## Returns item's instance data value for [param key].
## [br][br]
## Returns [param default] if the item or key is missing.
func get_item_data(item_id: int, key: StringName, default: Variant = null) -> Variant:
	return get_item_data_dict_raw(item_id).get(key, default)


## Requests an update to an item's data.
##[br][br]
## Can be called on both server and client. When called on client, execution does not happen immediately. 
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


## Generates a globally unique 64-bit ID instantly. The high 32 bits hold the
## creating peer's ID, the low 32 bits a per-peer sequence, so peers never collide.
func generate_id() -> int:
	_id_count += 1
	return (multiplayer.get_unique_id() << 32) | _id_count
