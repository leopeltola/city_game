class_name PlayerInventory
extends Node

## Emitted whenever the inventory contents or active slot changes.
signal inventory_updated()

@export var player: Player = null
@export var slot_count := 4
@export var item_slots: Array[int] = []

## Index of the currently selected slot. Setting this updates the equipped item.
@export var active_index := 0:
	set(val):
		active_index = val
		_equip_item(active_index)
		inventory_updated.emit()

@export var _equip_slot: Node3D = null

var _equipped_node: ItemEquip = null


func _ready() -> void:
	if item_slots.is_empty():
		item_slots.resize(slot_count)
		item_slots.fill(-1)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed("scroll_down"):
		active_index = wrapi(active_index - 1, 0, slot_count)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("scroll_up"):
		active_index = wrapi(active_index + 1, 0, slot_count)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("drop_item"):
		drop_active_item()
		get_viewport().set_input_as_handled()


## Return's the currently equipped item's idle anim override's name. Empty string == none
func get_idle_animation_override() -> String:
	return _equipped_node.idle_animation_override if _equipped_node else ""


## Returns the item ID at the specified index, or -1 if empty.
func get_item_at_idx(slot_idx: int) -> int:
	if slot_idx < 0 or slot_idx >= item_slots.size():
		return -1
	return item_slots[slot_idx]


## Attempts to store an item. Prioritizes the active slot, then the first free slot.
## Cash is merged into an existing cash item in the inventory instead of using a new slot.
## Returns true if the item was added.
func try_add_item_to_inv(item_id: int) -> bool:
	if ItemManager.get_item_data(item_id, "type") == "cash":
		var held_cash_id := find_item_id_of_type("cash")
		if held_cash_id != -1:
			var total: int = ItemManager.get_item_data(held_cash_id, "amount", 0) + ItemManager.get_item_data(item_id, "amount", 0)
			ItemManager.set_and_sync_item_data(held_cash_id, "amount", total)
			ItemManager.destroy_item(item_id)
			return true

	if not has_space():
		return false

	# 1. Fill active slot first if open
	if item_slots[active_index] == -1:
		_set_item(active_index, item_id)
		return true

	# 2. Fill first available slot from left to right
	for i in item_slots.size():
		if item_slots[i] == -1:
			_set_item(i, item_id)
			return true

	return false


## Returns true if there is at least one free slot.
func has_space() -> bool:
	return item_slots.has(-1)


## Returns the item ID of the first item of the given type in the inventory, or -1 if none.
func find_item_id_of_type(item_type_name: StringName) -> int:
	for i in item_slots.size():
		var item_id := item_slots[i]
		if item_id != -1 and ItemManager.get_item_data(item_id, "type") == item_type_name:
			return item_id
	return -1


## Removes and returns the item ID currently held in the active slot, or -1 if empty.
func pop_active_item() -> int:
	var item_id := get_item_at_idx(active_index)
	if item_id == -1:
		return -1

	_set_item(active_index, -1)
	return item_id


## Drops the item currently held in the active slot as a world item in front of the player.
func drop_active_item() -> void:
	var item_id := pop_active_item()
	if item_id == -1:
		return

	var camera := player.sight_pivot.get_node_or_null("Camera3D") as Camera3D
	var forward := -camera.global_transform.basis.z if camera else -player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var drop_pos := player.global_position + forward * 1.5 + Vector3.UP * 0.5
	ItemManager.create_world_item_for(item_id, drop_pos)


func _set_item(slot_idx: int, item_id: int) -> void:
	item_slots[slot_idx] = item_id
	if slot_idx == active_index:
		_equip_item(active_index)
	inventory_updated.emit()


func _equip_item(slot_idx: int) -> void:
	if is_instance_valid(_equipped_node):
		_equipped_node.queue_free()
		_equipped_node = null

	var item_id := get_item_at_idx(slot_idx)
	if item_id == -1:
		return

	var type: ItemType = ItemManager.get_item_type(ItemManager.get_item_data(item_id, "type"))
	var equipped_item: ItemEquip = type.get_equip_item_scene().instantiate()

	equipped_item.item_id = item_id
	equipped_item.interact_ray = %InteractRay
	equipped_item.player = player
	_equipped_node = equipped_item

	_equip_slot.add_child(equipped_item)
