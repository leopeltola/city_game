class_name PropSystem
extends Node
## Owns the body prop slots: which item is worn in each slot and the mounted visual
## nodes. worn_slots replicates to every peer (via the shared base synchronizer) so
## everyone shows the same outfit; the setter diffs and mounts/unmounts the visuals.
##
## Actors with a full inventory route a popped prop back into it; actors without one
## (e.g. citizens) drop it as a world item instead - see wear()'s return value.

## Body slots a prop (clothing/accessory) can be worn on. NONE = not a wearable prop.
enum PropSlot { NONE, TORSO, HAT, BEARD, GLASSES, HAND, COUNT }

## Slot item ids. -1 == empty. Replaced on remote peers by the MultiplayerSynchronizer;
## the setter keeps the worn visuals in sync.
@export var worn_slots: Array[int] = []:
	set(val):
		var old := worn_slots
		worn_slots = val
		if not is_inside_tree():
			return
		for i in worn_slots.size():
			var was := -1 if i >= old.size() else old[i]
			if worn_slots[i] != was:
				_unmount_slot(i)
				if worn_slots[i] != -1:
					_mount_slot(i, worn_slots[i])

## Body slot mount points (bone attachments on the shared rig). HAT/BEARD/GLASSES
## share the head bone and differ only in the authored worn pose.
@onready var _slot_nodes: Dictionary = {
	PropSystem.PropSlot.TORSO: %TorsoSlot,
	PropSystem.PropSlot.HAT: %HeadItemSlot,
	PropSystem.PropSlot.BEARD: %HeadItemSlot,
	PropSystem.PropSlot.GLASSES: %HeadItemSlot,
	PropSystem.PropSlot.HAND: %HandSlot,
}


func _ready() -> void:
	if worn_slots.is_empty():
		worn_slots.resize(PropSystem.PropSlot.COUNT)
		worn_slots.fill(-1)

	if not get_parent().is_local:
		%HeadItemSlot.show()
		%TorsoSlot.show()

	refresh_base_body()


## Shows/hides the owner's base body mesh so a worn torso prop replaces it. The locally
## simulated actor (first-person player) keeps its own body hidden.
func refresh_base_body() -> void:
	var humanoid := owner as Humanoid
	if humanoid == null or humanoid.body_mesh == null:
		return
	humanoid.body_mesh.visible = not humanoid.is_local and not _is_torso_worn()


## True while a prop is mounted in the TORSO slot, whether worn via [method wear] or a
## visual-only [method mount_visual] loadout (NPC clothing).
func _is_torso_worn() -> bool:
	var slot_node := _slot_nodes.get(PropSystem.PropSlot.TORSO) as Node3D
	if slot_node == null:
		return false
	for child in slot_node.get_children():
		if child is ItemEquip and not child.is_queued_for_deletion():
			return true
	return false


## Wears [param item_id] in [param slot], returning the previously worn item id (or -1).
func wear(item_id: int, slot: PropSystem.PropSlot) -> int:
	assert(is_multiplayer_authority(), "Can only be called on the multiplayer authority (owning client)")
	if slot <= PropSystem.PropSlot.NONE or slot >= PropSystem.PropSlot.COUNT:
		return -1
	var previous := get_worn_item_id(slot)
	_unmount_slot(slot)
	worn_slots[slot] = item_id
	_mount_slot(slot, item_id)
	return previous


## Removes and returns the item worn in [param slot] (or -1). Backend for the unequip menu.
func unwear(slot: PropSystem.PropSlot) -> int:
	assert(is_multiplayer_authority(), "Can only be called on the multiplayer authority (owning client)")
	var item_id := get_worn_item_id(slot)
	if item_id == -1:
		return -1
	_unmount_slot(slot)
	worn_slots[slot] = -1
	return item_id


## Returns the item id worn in [param slot], or -1 if empty.
func get_worn_item_id(slot: PropSystem.PropSlot) -> int:
	if slot < 0 or slot >= worn_slots.size():
		return -1
	return worn_slots[slot]


func is_slot_occupied(slot: PropSystem.PropSlot) -> bool:
	return get_worn_item_id(slot) != -1


## Returns the node props in [param slot] mount under (null for NONE).
func get_slot_node(slot: PropSystem.PropSlot) -> Node3D:
	return _slot_nodes.get(slot) as Node3D


## Mounts a worn visual from an [param type] alone (no backing item id). Used by static
## loadouts (e.g. NPC clothing): does not touch worn_slots and is not replicated.
func mount_visual(type: ItemType, slot: PropSystem.PropSlot) -> void:
	if type == null or slot <= PropSystem.PropSlot.NONE or slot >= PropSystem.PropSlot.COUNT:
		return
	_unmount_slot(slot)
	_instantiate_worn(slot, type, -1)


func _mount_slot(slot: PropSystem.PropSlot, item_id: int) -> void:
	var type := ItemManager.get_item_type(ItemManager.get_item_data(item_id, "type"))
	if type == null:
		return
	_instantiate_worn(slot, type, item_id)


# Adds a worn equip visual for [param type] under [param slot]'s mount node. A
# [param item_id] of -1 marks a visual-only prop with no ItemManager backing.
func _instantiate_worn(slot: PropSystem.PropSlot, type: ItemType, item_id: int) -> void:
	var slot_node := _slot_nodes.get(slot) as Node3D
	if slot_node == null:
		return
	var scene := type.get_equip_item_scene()
	if scene == null:
		return
	var equip: PropEquip = scene.instantiate()
	equip.worn = true
	equip.item_type = type
	equip.item_id = item_id
	equip.player = owner as Humanoid
	slot_node.add_child(equip)
	if slot == PropSystem.PropSlot.TORSO:
		refresh_base_body()


func _unmount_slot(slot: PropSystem.PropSlot) -> void:
	var slot_node := _slot_nodes.get(slot) as Node3D
	if slot_node == null:
		return
	for child in slot_node.get_children():
		if child is ItemEquip and child.item_type and child.item_type.prop_slot == slot:
			child.queue_free()
	if slot == PropSystem.PropSlot.TORSO:
		refresh_base_body()
