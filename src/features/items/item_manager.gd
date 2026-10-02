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


## Emitted on every peer when an existing item's instance data changes.
signal item_data_changed(item_id: int, key: StringName)

## Emitted on every peer when an item is destroyed.
signal item_destroyed(item_id: int)


const _item_types: Dictionary[StringName, ItemType] = {
	"lock_pick_set": preload("res://src/features/items/data/lock_picking/lock_pick_set/lock_pick_set.tres"),
	"saxophone": preload("res://src/features/items/data/saxophone/saxophone.tres"),
	"drum_sticks": preload("res://src/features/items/data/drum_sticks/drum_sticks.tres"),
	"cigar": preload("res://src/features/items/data/cigar/cigar.tres"),
	"briefcase": preload("res://src/features/items/data/briefcase/briefcase.tres"),
	"debit_card": preload("res://src/features/items/data/debit_card/debit_card.tres"),
	"bandana": preload("res://src/features/items/data/bandana/bandana.tres"),
	"hoodie": preload("res://src/features/items/data/hoodie/hoodie.tres"),
	"ski_mask": preload("res://src/features/items/data/ski_mask/ski_mask.tres"),
	"circle_glasses": preload("res://src/features/items/data/circle_glasses/circle_glasses.tres"),
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
	# A spawn may have registered this item first from a client payload; keep the runtime
	# fields it already applied (position, owner, launch_force) instead of resetting them.
	if _items.has(item_id):
		data.merge(_items[item_id], true)
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

	var data: Dictionary = _items.get(item_id, { })
	if data.is_empty():
		push_warning("ItemManager.create_world_item_for: unknown item id %d" % item_id)
		return

	if Net.is_server:
		_rpc_create_world_item_for(item_id, position, rotation, force, owner_player_id, data)
	elif Net.is_client:
		_rpc_create_world_item_for.rpc_id(1, item_id, position, rotation, force, owner_player_id, data)


@rpc("any_peer", "call_local", "reliable")
func _rpc_create_world_item_for(item_id: int, position: Vector3, rotation: Vector3 = Vector3.ZERO, force: Vector3 = Vector3.ZERO, owner_player_id: int = 0, data: Dictionary = { }) -> void:
	assert(Net.is_server)

	# A client-created item may not be registered on the server yet (or was already
	# destroyed). Rebuild it from the payload the caller sent along, and tell every peer.
	if not _items.has(item_id):
		if data.is_empty():
			push_warning("ItemManager: dropped world spawn for unknown item id %d" % item_id)
			return
		_items[item_id] = data
		_rpc_create_item.rpc(data)

	var spawn_data: Dictionary = _items[item_id]
	spawn_data["position"] = position
	spawn_data["rotation"] = rotation
	spawn_data["launch_force"] = force
	if owner_player_id:
		spawn_data["owner"] = owner_player_id # player id, 0 = none
	ItemMultiplayerSpawner.instance.spawn(spawn_data)


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
	for node: Node in get_tree().get_nodes_in_group("world_item"):
		if node is ItemWorld and node.item_id == item_id:
			node.play_despawn()
	item_destroyed.emit(item_id)


## Returns true if [param item_id] is a live item.
func has_item(item_id: int) -> bool:
	return _items.has(item_id)


## Returns item's instance data value for [param key].
## [br][br]
## Returns [param default] if the item or key is missing.
func get_item_data(item_id: int, key: StringName, default: Variant = null) -> Variant:
	return _items.get(item_id, { }).get(key, default)


## Returns the monetary value (€) of [param item_id]: cash stacks are worth their
## instance `money`, everything else its type's [member ItemType.base_value].
func get_item_value(item_id: int) -> int:
	var type_name: Variant = get_item_data(item_id, "type")
	if type_name == null:
		return 0
	if StringName(type_name) == &"cash":
		return int(get_item_data(item_id, "money", 0))
	return get_item_type(type_name).base_value


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
	item_data_changed.emit(item_id, key)


## Returns every live item id whose type name matches [param type_name].
func get_item_ids_by_type(type_name: StringName) -> Array[int]:
	var ids: Array[int] = []
	for item_id: int in _items:
		if StringName(_items[item_id].get("type", &"")) == type_name:
			ids.append(item_id)
	return ids


## Server-side: after crimes are accepted, reduce every photo that captured them to the
## guilt it can still claim, destroying any photo left with nothing. Works whether the
## photo is on the ground or in an inventory.
func invalidate_photos_for_guilt(accepted_ids: Dictionary) -> void:
	if not Net.is_server:
		return
	for item_id: int in get_item_ids_by_type(&"photo"):
		var entries: Dictionary = get_item_data(item_id, "guilt_entries", {})
		if entries.is_empty():
			continue
		var touched := false
		var remaining := 0
		for id: Variant in entries:
			if accepted_ids.has(int(id)):
				touched = true
			else:
				remaining += int(entries[id])
		if not touched:
			continue
		if remaining <= 0:
			destroy_item(item_id)
		else:
			set_and_sync_item_data(item_id, &"guilt", remaining)


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
