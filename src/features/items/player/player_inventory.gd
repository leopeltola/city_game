class_name PlayerInventory
extends Node

# Responsible for the player inventory

signal active_item_changed()

@export var player: Player = null
@export var tool_slot_count := 1
@export var item_slot_count := 3
@export var active_index := 0: # 0 = -1 = forced nothing equipped (for anims etc), tool slot, , 1+ = item
	set(val):
		active_index = val
		active_item_changed.emit()

var _equipped_node: ItemEquip = null
@export var _equip_slot: Node3D = null
var _equip_right_hand_target: Node3D = null
var _equit_tween: Tween

@export var tool_slots: Array[int] = []
@export var item_slots: Array[int] = []


func _ready() -> void:
	_setup()
	active_item_changed.connect(
		func():
			_equip_item(active_index)
	)
	
	print(player)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed("scroll_down"):
		print("Inv of local Player (ID %s) changed" % player.player_id)
		active_index = wrapi(active_index - 1, 0, 4)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("scroll_up"):
		print("Inv of local Player (ID %s) changed" % player.player_id)
		active_index = wrapi(active_index + 1, 0, 4)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	# Sync hand iks
	if is_instance_valid(_equip_right_hand_target):
		%RightHandIKTarget.global_transform = _equip_right_hand_target.global_transform


## Returns item_id, -1 if nothing there
func get_item_at_idx(slot_idx: int) -> int:
	if slot_idx == 0:
		return tool_slots[slot_idx]
	else:
		return item_slots[slot_idx - 1]


## Tries to add an item to inv. Returns whether it was succesful
func try_add_item_to_inv(item_id: int) -> bool:
	var item_data := ItemManager.get_item_data_dict_by_id(item_id)
	print(item_data)
	var type: ItemType = ItemManager.get_item_type(item_data["type"])

	if not has_space_for(type):
		return false

	# Find out where to put the item

	# First try active slot
	var active_id_item_slots_remap := active_index - 1 # Account for tool slot
	if active_index != 0 and item_slots[active_id_item_slots_remap] == -1:
		_set_item(active_index, item_id)
		return true

	# Then try to just put it somewhere (left->right
	for i in item_slots.size():
		if item_slots[i] == -1:
			_set_item(i + 1, item_id)
			return true

	return false


## Slot: 0 = tool slot, 1+ = item slots
## ItemID: -1 = null
func _set_item(slot: int, item_id: int) -> void:
	var item_data := ItemManager.get_item_data_dict_by_id(item_id)
	if slot != 0:
		item_slots[slot - 1] = item_id
	if slot == 0:
		# Item slot
		tool_slots[slot] = item_id
	print(item_slots)


func has_space_for(_item_type: ItemType) -> bool:
	for i in item_slots.size():
		if item_slots[i] == -1:
			return true
	return false


func _setup() -> void:
	for i in tool_slot_count:
		tool_slots.append(-1)
	for i in item_slot_count:
		item_slots.append(-1)


func _equip_item(slot_idx: int) -> void:
	if _equipped_node != null:
		_equipped_node.queue_free()
		_equipped_node = null
		_equipped_node = null
		
		
	
	var item_id: int = get_item_at_idx(slot_idx)

	if item_id == -1:
		if _equit_tween:
			_equit_tween.kill()
		_equit_tween = create_tween()
		_equit_tween.tween_property(%RightHandIK, "influence", 0, 0.1)
		_equit_tween.tween_property(%RightHandCopyTransform, "influence", 0, 0.1)
		_equit_tween.tween_property(%RightHandTwist, "influence", 0, 0.1)
		return
	
	var data := ItemManager.get_item_data_dict_by_id(item_id)
	var type: ItemType = ItemManager.get_item_type(data["type"])
	var equipped_item: ItemEquip = type.get_equip_item_scene().instantiate()
	equipped_item.interact_ray = %InteractRay
	equipped_item.player = player
	_equip_right_hand_target = equipped_item.right_hand_ik_target
	
	_equipped_node = equipped_item
	_equip_slot.add_child(equipped_item)
	
	if _equip_right_hand_target:
		if _equit_tween:
			_equit_tween.kill()
		_equit_tween = create_tween()
		_equit_tween.tween_property(%RightHandIK, "influence", 1, 0.1)
		_equit_tween.tween_property(%RightHandCopyTransform, "influence", 1, 0.1)
		_equit_tween.tween_property(%RightHandTwist, "influence", 1, 0.1)
