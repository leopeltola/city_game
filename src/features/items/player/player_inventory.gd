class_name PlayerInventory
extends EquipHost
## Slot-based item inventory for a player.
## 
## Currently also handles equipping props and equipping items. TODO: separate these
## into own modules. 
## [br][br]
## Network authority is held by the player's client, not server. This means most 
## write-operations have to be done on the specific client. 

## Emitted whenever a slot's contents or the active slot change, so UI can refresh.
signal inventory_updated()

## Maximum amount a single cash item can hold.
const CASH_STACK_LIMIT := 1000

## How long the drop item action must be held before the money-split prompt opens.
const DROP_LONG_PRESS_TIME := 0.5

## Camera gear toggled with the "camera" action. Unarmed gear with no backing slot:
## lowering the camera re-mounts the active slot's item.
const CAMERA_EQUIP_SCENE: PackedScene = preload("res://src/features/items/data/camera/camera_equip.tscn")

## Number of item slots. Used to size [member item_slots] on ready.
@export var slot_count := 4

## Replicated slot contents (item ID per slot, -1 == empty). Replaced by the
## MultiplayerSynchronizer on remote peers; the setter keeps the equipped visual in sync.
@export var item_slots: Array[int] = []:
	set(value):
		item_slots = value
		if is_inside_tree():
			_equip_item(active_index)
			inventory_updated.emit()

## Index of the currently selected slot. Setting this updates the equipped item.
@export var active_index := 0:
	set(value):
		active_index = value
		_equip_item(active_index)
		inventory_updated.emit()

## True while the camera is out. Replicated so every peer mounts the same visual.
## While up, the active slot's item stays stowed and is re-mounted when lowered.
@export var camera_out := false:
	set(value):
		var changed := camera_out != value
		camera_out = value
		if changed and is_inside_tree():
			if camera_out:
				_equip_camera()
			else:
				_equip_item(active_index)

var _drop_press_timer: SceneTreeTimer = null


func _ready() -> void:
	assert(slot_count > 0, "PlayerInventory.slot_count must be positive")
	assert(%InteractRay != null, "PlayerInventory requires an %InteractRay node")
	assert(%ItemDropRay != null, "PlayerInventory requires an %ItemDropRay node")
	assert(%ItemDropPosition != null, "PlayerInventory requires an %ItemDropPosition node")

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
		_lower_camera_if_out()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("scroll_up"):
		active_index = wrapi(active_index + 1, 0, slot_count)
		_lower_camera_if_out()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera"):
		camera_out = not camera_out
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("drop_item"):
		if camera_out:
			# No held item while the camera is up; swallow press and release.
			get_viewport().set_input_as_handled()
			return
		if _drop_press_timer == null:
			_drop_press_timer = get_tree().create_timer(DROP_LONG_PRESS_TIME)
			_drop_press_timer.timeout.connect(_on_drop_press_held)
		get_viewport().set_input_as_handled()
	elif event.is_action_released("drop_item"):
		if camera_out:
			get_viewport().set_input_as_handled()
			return
		if _drop_press_timer:
			_drop_press_timer.timeout.disconnect(_on_drop_press_held)
			_drop_press_timer = null
			drop_active_item()
		get_viewport().set_input_as_handled()


# Scrolling to another slot lowers the camera, mounting that slot's item.
func _lower_camera_if_out() -> void:
	if camera_out:
		camera_out = false


## Returns the item ID held in [param slot_index], or -1 if the slot is empty.
## [br][br]
## Asserts when [param slot_index] is outside the slot range, so callers must pass a
## valid slot (see [member item_slots] for the range).
func get_slot_item_id(slot_index: int) -> int:
	assert(
		slot_index >= 0 and slot_index < item_slots.size(),
		"slot_index %d out of range [0, %d)" % [slot_index, item_slots.size()],
	)
	return item_slots[slot_index]


## Attempts to store [param item_id] in the inventory.
## [br][br]
## Regular items fill the active slot first, then the first free slot. Cash fills
## existing cash stacks first and starts new stacks up to [constant CASH_STACK_LIMIT].
## [br][br]
## Returns true if the item was added.
## [br][br]
## Authority-only. 
func try_add_item(item_id: int) -> bool:
	assert(is_multiplayer_authority(), "try_add_item is authority-only")
	assert(
		not ItemManager.get_item_data_dict_raw(item_id).is_empty(),
		"try_add_item called with unknown item ID %d" % item_id,
	)

	if ItemManager.get_item_data(item_id, "type") == "cash":
		return _try_add_cash(item_id)

	var slot := _find_free_slot()
	if slot == -1:
		return false

	_set_item(slot, item_id)
	return true


## Puts [param item_id] in the inventory (priority: active slot, then first free slot).
## If camera (special case) is out, it's unequipped.
## [br][br]
## Returns false if there is no space for the item.
## [br][br]
## Authority-only. 
func pickup_item(item_id: int) -> bool:
	assert(is_multiplayer_authority(), "Must be called on the authority")

	var slot := _find_free_slot()
	if slot == -1:
		return false

	# Store first, then select, then lower the camera
	_set_item(slot, item_id)
	if slot != active_index:
		active_index = slot
	if camera_out:
		camera_out = false
	return true


## Wears the prop held in the active slot onto its body slot. Replaces any prop in
## that slot: the old one returns to the inventory (or is dropped if it doesn't fit).
## [br][br]
## Authority-only.
func wear_item(item_id: int) -> void:
	assert(is_multiplayer_authority(), "wear_item is authority-only")

	if get_active_item_id() != item_id:
		return
	var item_data := ItemManager.get_item_data_dict_raw(item_id)
	if item_data.is_empty():
		return
	var type := ItemManager.get_item_type(item_data["type"])
	if type == null or type.prop_slot == PropSystem.PropSlot.NONE:
		return
	var prop_system := player.prop_system
	if prop_system == null:
		return
	_set_item(active_index, -1)
	var popped := prop_system.wear(item_id, type.prop_slot)
	if popped != -1 and not try_add_item(popped):
		ItemManager.create_world_item_for(popped, player.global_position + Vector3.UP, player.rotation)


## Removes the prop worn in [param slot] if there is one, returning it to the inventory (or dropping it if
## the inventory is full).
## [br][br]
## Authority-only.
func unwear_prop_slot(slot: PropSystem.PropSlot) -> void:
	assert(is_multiplayer_authority(), "Must be called on the network authority")

	var prop_system := player.prop_system
	if prop_system == null:
		return
	var item_id := prop_system.unwear(slot)
	if item_id != -1 and not try_add_item(item_id):
		ItemManager.create_world_item_for(item_id, player.global_position + Vector3.UP, player.rotation)


# Attempts to add cash to the inventory, respecting the per-stack cash limit.
# Fills existing cash stacks up to the limit, then starts a new stack in a free slot.
# If the remainder doesn't fit, it is left as a world item where it is (returning false).
func _try_add_cash(item_id: int) -> bool:
	var remaining: int = ItemManager.get_item_data(item_id, "money", 0)

	# 1. Fill existing cash stacks up to the stack limit.
	for i in item_slots.size():
		if remaining <= 0:
			break
		var held_id := item_slots[i]
		if held_id == -1:
			continue
		if ItemManager.get_item_data(held_id, "type") != "cash":
			continue
		var current: int = ItemManager.get_item_data(held_id, "money", 0)
		var space := CASH_STACK_LIMIT - current
		if space <= 0:
			continue
		var added := mini(space, remaining)
		ItemManager.set_and_sync_item_data(held_id, "money", current + added)
		remaining -= added

	if remaining <= 0:
		ItemManager.destroy_item(item_id)
		return true

	# 2. If a free slot exists and the remainder fits in a single stack, start a new stack there.
	var slot := _find_free_slot()
	if slot != -1 and remaining <= CASH_STACK_LIMIT:
		ItemManager.set_and_sync_item_data(item_id, "money", remaining)
		_set_item(slot, item_id)
		return true

	# 3. No room for the remainder: leave the money as a world item where it is,
	#    updated to the leftover amount so the visual reflects the partial pick-up.
	ItemManager.set_and_sync_item_data(item_id, "money", remaining)
	return false


## Returns true if there is at least one free slot.
func has_free_slot() -> bool:
	return item_slots.has(-1)


# Returns the index of the first free slot (active slot first), or -1 if the inventory is full.
func _find_free_slot() -> int:
	assert(item_slots.size() == slot_count, "item_slots must be sized to slot_count")
	assert(
		active_index >= 0 and active_index < item_slots.size(),
		"active_index %d out of range [0, %d)" % [active_index, item_slots.size()],
	)

	if item_slots[active_index] == -1:
		return active_index
	for i in item_slots.size():
		if item_slots[i] == -1:
			return i
	return -1


## Returns the item ID of the first item matching [param item_type_name] found scanning
## slots in order, or -1 if no such item is held.
func find_item_id_by_type(item_type_name: StringName) -> int:
	for i in item_slots.size():
		var item_id := item_slots[i]
		if item_id != -1 and ItemManager.get_item_data(item_id, "type") == item_type_name:
			return item_id
	return -1


## Removes and returns the item ID currently held in the active slot, or -1 if empty.
## [br][br]
## Authority-only.
func pop_active_item() -> int:
	assert(is_multiplayer_authority(), "pop_active_item is authority-only")

	var item_id := get_slot_item_id(active_index)
	if item_id == -1:
		return -1

	_set_item(active_index, -1)
	return item_id


## Returns the item ID currently held in the active slot, or -1 if empty.
func get_active_item_id() -> int:
	var item_id := get_slot_item_id(active_index)
	if item_id == -1:
		return -1
	return item_id


## Drops the item currently held in the active slot as a world item in front of the player.
## [br][br]
## Authority-only.
func drop_active_item() -> void:
	assert(is_multiplayer_authority(), "drop_active_item is authority-only")

	var item_id := pop_active_item()
	if item_id == -1:
		return

	ItemManager.create_world_item_for(item_id, _drop_position(), player.rotation)


## Removes a random non-empty item from the inventory and spawns it as a world item at
## [param position] with the given launch [param force].
## [br][br]
## Authority-only. Returns the item ID, or -1 if the inventory is empty.
func drop_random_item(position: Vector3, force: Vector3) -> int:
	assert(is_multiplayer_authority(), "drop_random_item is authority-only")

	var slots := _get_non_empty_slots()
	if slots.is_empty():
		return -1

	var slot: int = slots[randi() % slots.size()]
	var item_id := get_slot_item_id(slot)
	_set_item(slot, -1)
	ItemManager.create_world_item_for(item_id, position, Vector3.ZERO, force)
	return item_id


# Returns the indices of all slots currently holding an item.
func _get_non_empty_slots() -> Array[int]:
	var slots: Array[int] = []
	for i in item_slots.size():
		if item_slots[i] != -1:
			slots.append(i)
	return slots


# Fired when the drop action has been held long enough. For cash, opens a prompt
# asking how much to drop instead of dropping the whole stack.
func _on_drop_press_held() -> void:
	var item_id := get_slot_item_id(active_index)
	if item_id == -1:
		return
	if ItemManager.get_item_data(item_id, "type") != "cash":
		return

	_drop_press_timer = null
	_prompt_drop_cash(item_id)


# Opens the money prompt to ask how much cash to drop from the held stack.
func _prompt_drop_cash(item_id: int) -> void:
	if not HUD.instance:
		return
	var total: int = ItemManager.get_item_data(item_id, "money", 0)
	if total <= 0:
		return

	var result := await HUD.instance.prompt_money(total, total, "Drop money")
	if result.cancelled or result.amount <= 0:
		return
	if get_slot_item_id(active_index) != item_id:
		return

	drop_cash_amount(item_id, mini(result.amount, total))


## Drops a specific [param amount] from the cash stack held as [param item_id].
## If [param amount] covers the whole stack, the entire stack is dropped as-is.
## [br][br]
## Authority-only.
func drop_cash_amount(item_id: int, amount: int) -> void:
	assert(is_multiplayer_authority(), "drop_cash_amount is authority-only")

	var total: int = ItemManager.get_item_data(item_id, "money", 0)
	if total <= 0 or amount <= 0:
		return
	if amount >= total:
		drop_active_item()
		return

	if Net.is_server:
		_server_split_cash_drop(item_id, amount, _drop_position())
	elif Net.is_client:
		_server_split_cash_drop.rpc_id(1, item_id, amount, _drop_position())


# Splits a cash stack server-side: shrinks the held stack to the remainder and
# spawns the dropped portion as a new cash world item at [param position].
@rpc("any_peer", "call_remote", "reliable")
func _server_split_cash_drop(item_id: int, amount: int, position: Vector3) -> void:
	assert(Net.is_server)
	var total: int = ItemManager.get_item_data(item_id, "money", 0)
	if total <= 0 or amount <= 0 or amount >= total:
		return

	ItemManager.set_and_sync_item_data(item_id, "money", total - amount)
	var dropped_id: int = ItemManager.create_item_of_type("cash", { "money": amount })
	ItemManager.create_world_item_for(dropped_id, position)


# Returns a world position about 1.5m in front of the player, offset back from walls.
func _drop_position() -> Vector3:
	if not %ItemDropRay.is_colliding():
		return %ItemDropPosition.global_position

	var hit_pos: Vector3 = %ItemDropRay.get_collision_point()
	var ray_origin: Vector3 = %ItemDropRay.global_position
	var pull_dir: Vector3 = (ray_origin - hit_pos).normalized()

	return hit_pos + pull_dir * 0.2


# Writes a slot directly on the authority and re-mounts the equip when the slot is active.
func _set_item(slot_index: int, item_id: int) -> void:
	assert(is_multiplayer_authority(), "_set_item is authority-only")
	assert(
		slot_index >= 0 and slot_index < item_slots.size(),
		"slot_index %d out of range [0, %d)" % [slot_index, item_slots.size()],
	)

	item_slots[slot_index] = item_id
	if slot_index == active_index:
		_equip_item(active_index)
	inventory_updated.emit()


# Mounts the item held in [param slot_index], or the unarmed fists when the slot is
# empty. Runs on every peer (also from the replicated setters), so it tolerates an
# unsized/empty slot array instead of asserting.
func _equip_item(slot_index: int) -> void:
	if camera_out:
		# Camera is up; slot changes are UI-only until it comes down.
		return
	if _equip_root == null:
		return
	_remove_equipped_node()

	if slot_index < 0 or slot_index >= item_slots.size():
		mount_unarmed()
		return

	var item_id := item_slots[slot_index]
	if item_id == -1:
		mount_unarmed()
		return

	# The item may have been destroyed (e.g. full cash insert into the slot
	# machine) while a stale slot snapshot is still being replicated. Guard
	# against it so we never hand a nil type name to get_item_type().
	var item_data := ItemManager.get_item_data_dict_raw(item_id)
	if item_data.is_empty():
		push_error("Tried equipping item but item_id not found: ID: %s\nitem_data: %s" % [item_id, item_data])
		item_slots[slot_index] = -1
		inventory_updated.emit()
		mount_unarmed()
		return

	var type: ItemType = ItemManager.get_item_type(item_data["type"])
	var equipped_item: ItemEquip = type.get_equip_item_scene().instantiate()

	equipped_item.item_id = item_id
	equipped_item.interact_ray = %InteractRay
	equipped_item.player = player
	_equipped_node = equipped_item

	_equip_root.add_child(equipped_item)


# Mounts the camera gear, replacing the current equip. Lowering re-mounts the
# active slot's item (or fists).
func _equip_camera() -> void:
	if _equip_root == null:
		return
	# Cancel any in-flight drop long-press started before the toggle; its release is
	# swallowed while the camera is up.
	_cancel_drop_press_timer()
	_remove_equipped_node()
	var camera: ItemEquip = CAMERA_EQUIP_SCENE.instantiate()
	camera.player = player
	camera.interact_ray = %InteractRay
	_equipped_node = camera
	_equip_root.add_child(camera)


# Cancels an in-flight drop long-press timer.
func _cancel_drop_press_timer() -> void:
	if _drop_press_timer:
		_drop_press_timer.timeout.disconnect(_on_drop_press_held)
		_drop_press_timer = null
