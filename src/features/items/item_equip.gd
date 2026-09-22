class_name ItemEquip
extends Node3D
## Base for anything mounted in the player's equipped-hand slot. Two kinds exist:
##  - real world items (an ItemType + an ItemManager instance id), e.g. bat, cash, crate
##  - unarmed "gear" with no backing item (see is_unarmed()), e.g. the bare fists
##
## The equip scene parents under the player's neutral %EquipRoot (which stays put).
## Per-hand content (visuals, hit shapes) lives inside HandAnchor children; on mount
## a RemoteTransform3D is created under the matching hand slot that pushes the slot's
## hand-bone transform onto each anchor every frame - so anchors follow the hands
## without being reparented. Equips that need to sample hand motion should use
## get_hand_global_transform() rather than their own transform (the root is static).
##
## Subclasses drive gameplay (attack, carry, ...). They talk to the owner through
## `player` and, for animation, through player.animator - never the AnimationPlayer
## directly.

const InteractRay := preload("res://src/features/interaction/interact_ray.gd")

## Item type this equip visualizes. Null for unarmed gear (fists).
@export var item_type: ItemType = null
## Idle animation override reported to PlayerAnimator. Empty == the player's default idle.
@export var idle_animation_override := ""

## ItemManager instance id. -1 means "not backed by an item", valid for unarmed gear.
var item_id: int = -1
var interact_ray: InteractRay = null
var player: Humanoid = null

var _ready_done := false

## HandAnchor -> RemoteTransform3D driving it to its hand slot.
var _anchor_drivers: Dictionary = {}


## True when this equip is not backed by a real item (e.g. bare fists).
func is_unarmed() -> bool:
	return item_type == null and item_id == -1


func _ready() -> void:
	assert(player, "ItemEquip requires player to be set before it is added to the tree")
	if not is_unarmed():
		assert(item_type, "Item equips require item_type")
		assert(item_id != -1, "Item equips require a valid item_id")
	_ready_done = true
	_on_equipped()


func _exit_tree() -> void:
	if _ready_done:
		_on_unequipped()
	_ready_done = false


## Called once, after asserts pass, when the equip is mounted. Subclasses override and
## call super() to also attach hand anchors.
func _on_equipped() -> void:
	_attach_hand_anchors()


## Called when this equip leaves the tree (swap / unequip / player freed). Subclasses
## override and call super() to release hand anchors.
func _on_unequipped() -> void:
	_detach_hand_anchors()


## Creates a RemoteTransform3D under each HandAnchor's hand slot that pushes the slot
## (hand bone) transform onto the anchor every frame.
func _attach_hand_anchors() -> void:
	if player == null or player.equipment == null:
		return
	for child in get_children():
		if child is HandAnchor:
			_drive_anchor(child)


func _drive_anchor(anchor: HandAnchor) -> void:
	if _anchor_drivers.has(anchor):
		return
	var slot: Node3D = player.equipment.get_hand_slot(anchor.hand)
	if slot == null:
		return
	var rt := RemoteTransform3D.new()
	rt.name = "HandDriver_" + anchor.name
	rt.update_scale = false
	slot.add_child(rt)
	rt.remote_path = rt.get_path_to(anchor)
	_anchor_drivers[anchor] = rt


## Frees the driver RemoteTransforms (they live under the player's hand slots, outside
## this equip's subtree, so they must be cleaned up explicitly).
func _detach_hand_anchors() -> void:
	for rt: RemoteTransform3D in _anchor_drivers.values():
		if is_instance_valid(rt):
			rt.queue_free()
	_anchor_drivers.clear()


## Returns the HandAnchor for a hand side, or null if this equip doesn't use it.
func get_hand_anchor(hand: HandAnchor.HandSide) -> HandAnchor:
	for child in get_children():
		if child is HandAnchor and child.hand == hand:
			return child
	return null


## Returns the current world transform of a hand's anchor (i.e. where that hand bone
## is). Equips whose root is static (neutral %EquipRoot) should sample this instead of
## their own transform for anything that depends on hand motion.
func get_hand_global_transform(hand: HandAnchor.HandSide) -> Transform3D:
	var anchor := get_hand_anchor(hand)
	if anchor == null:
		return global_transform
	return anchor.global_transform
