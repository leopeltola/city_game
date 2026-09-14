class_name EquipHost
extends Node
## Shared equip mounting for actors (players with a full inventory, NPCs with fixed
## gear). Holds the neutral %EquipRoot and the hand slots, mounts/unmounts the current
## ItemEquip (or the unarmed fists when no item is held) and reports the equipped
## idle-animation override to the ActorAnimator.
##
## PlayerInventory extends this with slot management, cash, camera gear and the
## drop/pickup UI; NPCs use it directly to mount fixed equipment.

## Mounted when no item is equipped so the actor can always fight (bare fists).
## Unlike real items this is unarmed "gear": no ItemType, no ItemManager instance id.
const UNARMED_EQUIP_SCENE: PackedScene = preload("res://src/features/items/data/fists/fists_equip.tscn")

## The actor this host belongs to. Equips reach the actor's animator/status through it.
@export var player: Humanoid = null
## Neutral mount that the whole equip scene parents under (stays put). Per-hand
## content inside the equip is driven to the hand slots via HandAnchors instead.
@export var _equip_root: Node3D = null
## Hand bone slots the HandAnchors get their transforms pushed from.
@export var _right_equip_slot: Node3D = null
@export var _left_equip_slot: Node3D = null

var _equipped_node: ItemEquip = null


## Returns the hand slot node for a given hand side (driven by that hand's bone).
func get_hand_slot(hand: HandAnchor.HandSide) -> Node3D:
	match hand:
		HandAnchor.HandSide.LEFT:
			return _left_equip_slot
		_:
			return _right_equip_slot


## Returns the currently mounted equip node (item or unarmed gear like fists), or null.
func get_equipped_node() -> ItemEquip:
	return _equipped_node


## Returns the currently equipped item's idle anim override's name. Empty string == none.
func get_idle_animation_override() -> String:
	return _equipped_node.idle_animation_override if _equipped_node else ""


## Detaches the current equip immediately (not queue_free alone) so the next mount
## keeps the canonical scene-root name; otherwise Godot renames the new child (e.g.
## "FistsEquip2") and breaks the equip-node RPC path on peers.
func _remove_equipped_node() -> void:
	if not is_instance_valid(_equipped_node):
		return
	_equip_root.remove_child(_equipped_node)
	_equipped_node.queue_free()
	_equipped_node = null


## Mounts the bare-hands fists gear (unarmed, no backing item).
func mount_unarmed() -> void:
	if _equip_root == null or not is_instance_valid(player):
		return
	var fists: ItemEquip = UNARMED_EQUIP_SCENE.instantiate()
	fists.player = player
	_equipped_node = fists
	_equip_root.add_child(fists)