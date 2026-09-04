class_name PlayerInventory
extends Node

## Emitted whenever the inventory contents or active slot changes.
signal inventory_updated()

## Maximum amount of cash a single cash item can hold.
const CASH_STACK_LIMIT := 1000

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
## Cash fills existing cash stacks first and starts new stacks up to the cash stack limit.
## Returns true if the item was added.
func try_add_item_to_inv(item_id: int) -> bool:
	if ItemManager.get_item_data(item_id, "type") == "cash":
		return _try_add_cash(item_id)

	var slot := _find_free_slot()
	if slot == -1:
		return false

	_set_item(slot, item_id)
	return true


## Attempts to add cash to the inventory, respecting the per-stack cash limit.
## Fills existing cash stacks up to the limit, then starts a new stack in a free slot.
## If the remainder doesn't fit, it is left as a world item where it is (returning false).
func _try_add_cash(item_id: int) -> bool:
	var remaining: int = ItemManager.get_item_data(item_id, "amount", 0)

	# 1. Fill existing cash stacks up to the stack limit.
	for i in item_slots.size():
		if remaining <= 0:
			break
		var held_id := item_slots[i]
		if held_id == -1:
			continue
		if ItemManager.get_item_data(held_id, "type") != "cash":
			continue
		var current: int = ItemManager.get_item_data(held_id, "amount", 0)
		var space := CASH_STACK_LIMIT - current
		if space <= 0:
			continue
		var added := mini(space, remaining)
		ItemManager.set_and_sync_item_data(held_id, "amount", current + added)
		remaining -= added

	if remaining <= 0:
		ItemManager.destroy_item(item_id)
		return true

	# 2. If a free slot exists and the remainder fits in a single stack, start a new stack there.
	var slot := _find_free_slot()
	if slot != -1 and remaining <= CASH_STACK_LIMIT:
		ItemManager.set_and_sync_item_data(item_id, "amount", remaining)
		_set_item(slot, item_id)
		return true

	# 3. No room for the remainder: leave the money as a world item where it is,
	#    updated to the leftover amount so the visual reflects the partial pick-up.
	ItemManager.set_and_sync_item_data(item_id, "amount", remaining)
	return false


## Returns true if there is at least one free slot.
func has_space() -> bool:
	return item_slots.has(-1)


## Returns the index of the first free slot (active slot first), or -1 if the inventory is full.
func _find_free_slot() -> int:
	if item_slots[active_index] == -1:
		return active_index
	for i in item_slots.size():
		if item_slots[i] == -1:
			return i
	return -1


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

	ItemManager.create_world_item_for(item_id, _drop_position())


## Returns a world position about 1.5m in front of the player.
func _drop_position() -> Vector3:
	var camera := player.sight_pivot.get_node_or_null("Camera3D") as Camera3D
	var forward := -camera.global_transform.basis.z if camera else -player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	return player.global_position + forward * 1.5 + Vector3.UP * 0.5


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
