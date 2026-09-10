class_name PlayerInventory
extends Node

## Emitted whenever the inventory contents or active slot changes.
signal inventory_updated()

## Maximum amount of cash a single cash item can hold.
const CASH_STACK_LIMIT := 1000

## How long the drop item action must be held before the money-split prompt opens.
const DROP_LONG_PRESS_TIME := 0.5

## Mounted when the active slot is empty so the player can always fight (bare fists).
## Unlike real items this is unarmed "gear": no ItemType, no ItemManager instance id.
const UNARMED_EQUIP_SCENE: PackedScene = preload("res://src/features/items/data/fists/fists_equip.tscn")

@export var player: Player = null
@export var slot_count := 4

## Replicated slot contents (item ID per slot, -1 == empty). Replaced by the
## MultiplayerSynchronizer on remote peers; the setter keeps the equipped visual in sync.
@export var item_slots: Array[int] = []:
	set(val):
		item_slots = val
		if is_inside_tree():
			_equip_item(active_index)
			inventory_updated.emit()

## Index of the currently selected slot. Setting this updates the equipped item.
@export var active_index := 0:
	set(val):
		active_index = val
		_equip_item(active_index)
		inventory_updated.emit()

## Neutral mount that the whole equip scene parents under (stays put). Per-hand
## content inside the equip is driven to the hand slots via HandAnchors instead.
@export var _equip_root: Node3D = null
## Hand bone slots the HandAnchors get their transforms pushed from.
@export var _right_equip_slot: Node3D = null
@export var _left_equip_slot: Node3D = null

var _equipped_node: ItemEquip = null
var _drop_press_timer: SceneTreeTimer = null


## Returns the hand slot node for a given hand side (driven by that hand's bone).
func get_hand_slot(hand: HandAnchor.HandSide) -> Node3D:
	match hand:
		HandAnchor.HandSide.LEFT:
			return _left_equip_slot
		_:
			return _right_equip_slot


func _ready() -> void:
	if item_slots.is_empty():
		item_slots.resize(slot_count)
		item_slots.fill(-1)
	# The authority's own slot values don't arrive via replication, so mount whatever
	# the active slot holds (fists if empty) once here. Deferred: equipping spawns the
	# equip node whose _ready reaches into player.animator, which needs Player._ready
	# to have run first. Remote peers are covered by the replicated setters instead.
	_equip_item.call_deferred(active_index)


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	# While the money prompt is open, swallow the drop key — including the
	# auto-repeat of the still-held key — so it can't type into the LineEdit
	# and wipe the default value. Runs before GUI input, so the LineEdit never
	# sees it.
	if HUD.instance and HUD.instance.is_money_prompt_open() and event.is_action_pressed("drop_item", true):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or (HUD.instance and HUD.instance.is_blocking_input()):
		return
	# Stagger (or any action-locking status) prevents switching item slots.
	if player != null and player.is_action_locked() and (
		event.is_action_pressed("scroll_down") or event.is_action_pressed("scroll_up")
	):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("scroll_down"):
		active_index = wrapi(active_index - 1, 0, slot_count)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("scroll_up"):
		active_index = wrapi(active_index + 1, 0, slot_count)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("drop_item"):
		if _drop_press_timer == null:
			_drop_press_timer = get_tree().create_timer(DROP_LONG_PRESS_TIME)
			_drop_press_timer.timeout.connect(_on_drop_press_held)
		get_viewport().set_input_as_handled()
	elif event.is_action_released("drop_item"):
		if _drop_press_timer:
			_drop_press_timer.timeout.disconnect(_on_drop_press_held)
			_drop_press_timer = null
			drop_active_item()
		get_viewport().set_input_as_handled()


## Return's the currently equipped item's idle anim override's name. Empty string == none
func get_idle_animation_override() -> String:
	return _equipped_node.idle_animation_override if _equipped_node else ""


## Returns the currently mounted equip node (item or unarmed gear like fists), or null.
func get_equipped_node() -> ItemEquip:
	return _equipped_node


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

	ItemManager.create_world_item_for(item_id, _drop_position(), player.rotation)


## Removes a random non-empty item from the inventory and spawns it as a world item at
## [position] with the given launch [force]. Returns the item ID, or -1 if the inventory is empty.
func drop_random_item(position: Vector3, force: Vector3) -> int:
	var slots := _get_non_empty_slots()
	if slots.is_empty():
		return -1

	var slot: int = slots[randi() % slots.size()]
	var item_id := get_item_at_idx(slot)
	_set_item(slot, -1)
	ItemManager.create_world_item_for(item_id, position, Vector3.ZERO, force)
	return item_id


## Returns the indices of all slots currently holding an item.
func _get_non_empty_slots() -> Array[int]:
	var slots: Array[int] = []
	for i in item_slots.size():
		if item_slots[i] != -1:
			slots.append(i)
	return slots


## Fired when the drop action has been held long enough. For cash, opens a prompt
## asking how much to drop instead of dropping the whole stack.
func _on_drop_press_held() -> void:
	var item_id := get_item_at_idx(active_index)
	if item_id == -1:
		return
	if ItemManager.get_item_data(item_id, "type") != "cash":
		return

	_drop_press_timer = null
	_prompt_drop_cash(item_id)


## Opens the money prompt to ask how much cash to drop from the held stack.
func _prompt_drop_cash(item_id: int) -> void:
	if not HUD.instance:
		return
	var total: int = ItemManager.get_item_data(item_id, "amount", 0)
	if total <= 0:
		return

	var result := await HUD.instance.prompt_money(total, total, "Drop money")
	if result.cancelled or result.amount <= 0:
		return
	if get_item_at_idx(active_index) != item_id:
		return

	drop_cash_amount(item_id, mini(result.amount, total))


## Drops a specific [amount] from the cash stack held in [item_id]. If [amount]
## covers the whole stack, the entire stack is dropped as-is.
func drop_cash_amount(item_id: int, amount: int) -> void:
	var total: int = ItemManager.get_item_data(item_id, "amount", 0)
	if total <= 0 or amount <= 0:
		return
	if amount >= total:
		drop_active_item()
		return

	if Net.is_server:
		_server_split_cash_drop(item_id, amount, _drop_position())
	elif Net.is_client:
		_server_split_cash_drop.rpc_id(1, item_id, amount, _drop_position())


## Splits a cash stack server-side: shrinks the held stack to the remainder and
## spawns the dropped portion as a new cash world item at [position].
@rpc("any_peer", "call_remote", "reliable")
func _server_split_cash_drop(item_id: int, amount: int, position: Vector3) -> void:
	assert(Net.is_server)
	var total: int = ItemManager.get_item_data(item_id, "amount", 0)
	if total <= 0 or amount <= 0 or amount >= total:
		return

	ItemManager.set_and_sync_item_data(item_id, "amount", total - amount)
	var dropped_id: int = ItemManager.create_item_of_type("cash", { "amount": amount })
	ItemManager.create_world_item_for(dropped_id, position)


## Returns a world position about 1.5m in front of the player, offset back from walls.
func _drop_position() -> Vector3:
	if not %ItemDropRay.is_colliding():
		return %ItemDropPosition.global_position

	var hit_pos: Vector3 = %ItemDropRay.get_collision_point()
	var ray_origin: Vector3 = %ItemDropRay.global_position
	var pull_dir: Vector3 = (ray_origin - hit_pos).normalized()

	return hit_pos + pull_dir * 0.2


func _set_item(slot_idx: int, item_id: int) -> void:
	item_slots[slot_idx] = item_id
	if slot_idx == active_index:
		_equip_item(active_index)
	inventory_updated.emit()


func _equip_item(slot_idx: int) -> void:
	if _equip_root == null:
		return
	if is_instance_valid(_equipped_node):
		# Detach immediately (not just queue_free) so the new equip node gets the
		# canonical scene-root name. queue_free alone leaves the old node in the tree
		# until end-of-frame, and Godot renames the freshly added child (e.g. to
		# "FistsEquip2") - which breaks the RPC node path on peers that re-equip.
		_equip_root.remove_child(_equipped_node)
		_equipped_node.queue_free()
		_equipped_node = null

	var item_id := get_item_at_idx(slot_idx)
	if item_id == -1:
		_mount_unarmed()
		return

	# The item may have been destroyed (e.g. full cash insert into the slot
	# machine) while a stale slot snapshot is still being replicated. Guard
	# against it so we never hand a nil type name to get_item_type().
	var item_data := ItemManager.get_item_data_dict_raw(item_id)
	if item_data.is_empty():
		push_error("Tried equipping item but item_id not found: ID: %s\nitem_data: %s" % [item_id, item_data])
		item_slots[slot_idx] = -1
		inventory_updated.emit()
		_mount_unarmed()
		return

	var type: ItemType = ItemManager.get_item_type(item_data["type"])
	var equipped_item: ItemEquip = type.get_equip_item_scene().instantiate()

	equipped_item.item_id = item_id
	equipped_item.interact_ray = %InteractRay
	equipped_item.player = player
	_equipped_node = equipped_item

	_equip_root.add_child(equipped_item)


## Mounts the bare-hands fists gear when the active slot holds no item.
func _mount_unarmed() -> void:
	var fists: ItemEquip = UNARMED_EQUIP_SCENE.instantiate()
	fists.player = player
	_equipped_node = fists
	_equip_root.add_child(fists)
