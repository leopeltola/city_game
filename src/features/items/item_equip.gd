class_name ItemEquip
extends Node3D
## Base for anything mounted in the player's equipped-hand slot. Two kinds exist:
##  - real world items (an ItemType + an ItemManager instance id), e.g. bat, cash, crate
##  - unarmed "gear" with no backing item (see is_unarmed()), e.g. the bare fists
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
var player: Player = null

var _ready_done := false


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


## Called once, after asserts pass, when the equip is mounted. Override to set up
## (resolve children, connect signals, build runtime config).
func _on_equipped() -> void:
	pass


## Called when this equip leaves the tree (swap / unequip / player freed). Override
## to cancel active actions and restore player state (modifiers, animations, flags).
func _on_unequipped() -> void:
	pass
