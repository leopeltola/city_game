class_name PlayerInventory
extends Node

# Responsible for the player inventory

signal item_equipped(item)

@export var tool_slot_count := 1
@export var item_slot_count := 3
var active_index := 0 # 0 = tool slot, -1 = forced nothing equipped (for anims etc), 1+ = item


class InventoryItem extends RefCounted:
	var id: int
	var data: Dictionary:
		get:
			return ItemManager.get_item_data_dict_by_id(id)
	var node: Node = null


var tool_slots: Array[InventoryItem] = []
var item_slots: Array[InventoryItem] = []


func _ready() -> void:
	_setup()


## Tries to add an item to inv. Returns whether it was succesful
func try_add_item_to_inv(item) -> bool:
	if not has_space_for(item):
		return false
	return true


func has_space_for(item_type: ItemType) -> bool:
	for i in item_slots.size():
		if item_slots[i] == null:
			return true
	return false


func _setup() -> void:
	for i in tool_slot_count:
		tool_slots.append(null)
	for i in item_slot_count:
		item_slots.append(null)
