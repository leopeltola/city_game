class_name PlayerInventory
extends Node
## Slot-based item inventory for a player.
##
## Owns the item slots, the active selection, the add/remove/query operations and the
## player-facing input that drives them (slot scroll, camera toggle, drop long-press).
## Equipping is delegated to the actor's [EquipHost] and world drops to a child
## [ItemDropper]; worn props are moved in/out of the shared [PropSystem] directly.
## [br][br]
## Network authority is held by the player's client, not server. This means most
## write-operations have to be done on the specific client.

## Emitted whenever a slot's contents or the active slot change, so UI can refresh.
signal inventory_updated()

## Maximum amount a single cash item can hold.
const CASH_STACK_LIMIT := 1000

## How long the drop item action must be held before the money-split prompt opens.
const DROP_LONG_PRESS_TIME := 0.5

## The actor this inventory belongs to. Supplies the equip host, prop system and drops.
@export var player: Humanoid = null

## Number of item slots. Used to size [member item_slots] on ready.
@export var slot_count := 4

## Replicated slot contents (item ID per slot, -1 == empty). Replaced by the
## MultiplayerSynchronizer on remote peers; the setter keeps the equipped visual in sync.
@export var item_slots: Array[int] = []:
	set(value):
		item_slots = value
		if is_inside_tree():
			_refresh_equip()
			inventory_updated.emit()

## Index of the currently selected slot. Setting this updates the equipped item.
@export var active_index := 0:
	set(value):
		active_index = value
		if is_inside_tree():
			_refresh_equip()
			inventory_updated.emit()

@onready var _dropper: ItemDropper = $ItemDropper

var _drop_press_timer: SceneTreeTimer = null


func _ready() -> void:
	assert(player != null, "PlayerInventory requires player")
	assert(slot_count > 0, "PlayerInventory.slot_count must be positive")

	if item_slots.is_empty():
		item_slots.resize(slot_count)
		item_slots.fill(-1)
	# The authority's own slot values don't arrive via replication, so mount whatever
	# the active slot holds (fists if empty) once here. Deferred: equipping spawns the
	# equip node whose _ready reaches into player.animator, which needs Player._ready
	# to have run first. Remote peers are covered by the replicated setters instead.
	_refresh_equip.call_deferred()


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
	# Cuffed players can't switch, use or drop items.
	if player != null and player.get("arrested") == true:
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
		# Cancel any in-flight drop long-press started before the toggle; its release is
		# swallowed while the camera is up.
		_cancel_drop_press_timer()
		if is_instance_valid(player) and player.equipment != null:
			player.equipment.toggle_camera()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("drop_item"):
		if _is_camera_out():
			# No held item while the camera is up; swallow press and release.
			get_viewport().set_input_as_handled()
			return
		if _drop_press_timer == null:
			_drop_press_timer = get_tree().create_timer(DROP_LONG_PRESS_TIME)
			_drop_press_timer.timeout.connect(_on_drop_press_held)
		get_viewport().set_input_as_handled()
	elif event.is_action_released("drop_item"):
		if _is_camera_out():
			get_viewport().set_input_as_handled()
			return
		if _drop_press_timer:
			_drop_press_timer.timeout.disconnect(_on_drop_press_held)
			_drop_press_timer = null
			drop_active_item()
		get_viewport().set_input_as_handled()


# Re-mounts the equip host for the active slot (or the camera, which the host tracks).
func _refresh_equip() -> void:
	if is_instance_valid(player) and player.equipment != null:
		player.equipment.mount_active()


# Scrolling to another slot lowers the camera, mounting that slot's item.
func _lower_camera_if_out() -> void:
	if is_instance_valid(player) and player.equipment != null:
		player.equipment.lower_camera()


# True while the actor's camera gear is out.
func _is_camera_out() -> bool:
	return is_instance_valid(player) and player.equipment != null and player.equipment.is_camera_out()


# Cancels an in-flight drop long-press timer.
func _cancel_drop_press_timer() -> void:
	if _drop_press_timer:
		_drop_press_timer.timeout.disconnect(_on_drop_press_held)
		_drop_press_timer = null


# Fired when the drop action has been held long enough. For money containers (cash
# stacks and briefcases), opens a prompt asking how much to drop instead of dropping
# the whole item.
func _on_drop_press_held() -> void:
	var item_id := get_active_item_id()
	if item_id == -1:
		return
	var type := String(ItemManager.get_item_data(item_id, "type"))
	if type != "cash" and type != "briefcase":
		return

	_drop_press_timer = null
	_dropper.prompt_drop_money(item_id)


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
	if _is_camera_out():
		player.equipment.lower_camera()
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
		_dropper.spawn_item(popped, player.global_position + Vector3.UP, player.rotation)


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
		_dropper.spawn_item(item_id, player.global_position + Vector3.UP, player.rotation)


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
		if item_id != -1 and StringName(ItemManager.get_item_data(item_id, "type")) == item_type_name:
			return item_id
	return -1


## Removes [param item_id] from the inventory if present. Returns true if it was held.
## [br][br]
## Authority-only.
func remove_item(item_id: int) -> bool:
	assert(is_multiplayer_authority(), "remove_item is authority-only")

	for i in item_slots.size():
		if item_slots[i] == item_id:
			_set_item(i, -1)
			return true
	return false


## Removes and destroys every inventory item and every worn prop. Used when the police
## confiscate a player's belongings. [br][br]
## Authority-only.
func confiscate_all() -> void:
	assert(is_multiplayer_authority(), "confiscate_all is authority-only")

	if player != null and player.prop_system != null:
		for slot in range(PropSystem.PropSlot.NONE + 1, PropSystem.PropSlot.COUNT):
			var worn_id: int = player.prop_system.unwear(slot)
			if worn_id != -1:
				ItemManager.destroy_item(worn_id)

	for i in item_slots.size():
		var item_id := item_slots[i]
		if item_id == -1:
			continue
		_set_item(i, -1)
		ItemManager.destroy_item(item_id)


## Removes and returns the item ID currently held in the active slot, or -1 if empty.
## [br][br]
## Authority-only.
func pop_active_item() -> int:
	assert(is_multiplayer_authority(), "pop_active_item is authority-only")

	var item_id := get_active_item_id()
	if item_id == -1:
		return -1

	_set_item(active_index, -1)
	return item_id


## Removes and returns the ID of a random non-empty slot, or -1 if the inventory is empty.
## [br][br]
## Authority-only.
func pop_random_item() -> int:
	assert(is_multiplayer_authority(), "pop_random_item is authority-only")

	var slots := _get_non_empty_slots()
	if slots.is_empty():
		return -1

	var slot: int = slots[randi() % slots.size()]
	var item_id := get_slot_item_id(slot)
	_set_item(slot, -1)
	return item_id


## Returns the item ID currently held in the active slot, or -1 if empty.
func get_active_item_id() -> int:
	if active_index < 0 or active_index >= item_slots.size():
		return -1
	return item_slots[active_index]


## Drops the item currently held in the active slot as a world item in front of the player.
## [br][br]
## Authority-only.
func drop_active_item() -> void:
	_dropper.drop_active_item()


## Removes a random non-empty item from the inventory and spawns it as a world item at
## [param position] with the given launch [param force]. [param owner_player_id] marks
## the dropped item as owned so looting it counts as theft.
## [br][br]
## Authority-only. Returns the item ID, or -1 if the inventory is empty.
func drop_random_item(position: Vector3, force: Vector3, owner_player_id: int = 0) -> int:
	return _dropper.drop_random_item(position, force, owner_player_id)


## Drops a specific [param amount] of the money held by [param item_id].
## [br][br]
## Authority-only.
func drop_money_amount(item_id: int, amount: int) -> void:
	_dropper.drop_money_amount(item_id, amount)


## Clears the active slot when the item it referenced no longer exists. Runs on every
## peer (stale replicated snapshots can still point at destroyed items), so no authority
## assert. No-op if the slot changed since.
func clear_stale_active(item_id: int) -> void:
	if active_index < 0 or active_index >= item_slots.size():
		return
	if item_slots[active_index] == item_id:
		item_slots[active_index] = -1
		inventory_updated.emit()


# Returns the indices of all slots currently holding an item.
func _get_non_empty_slots() -> Array[int]:
	var slots: Array[int] = []
	for i in item_slots.size():
		if item_slots[i] != -1:
			slots.append(i)
	return slots


# Writes a slot directly on the authority and re-mounts the equip when the slot is active.
func _set_item(slot_index: int, item_id: int) -> void:
	assert(is_multiplayer_authority(), "_set_item is authority-only")
	assert(
		slot_index >= 0 and slot_index < item_slots.size(),
		"slot_index %d out of range [0, %d)" % [slot_index, item_slots.size()],
	)

	item_slots[slot_index] = item_id
	if slot_index == active_index:
		_refresh_equip()
	inventory_updated.emit()
