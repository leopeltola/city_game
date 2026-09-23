class_name NpcLoadout
extends Node
## Mounts a fixed, visual-only set of clothing props onto the parent Humanoid.
##
## The loadout is authored here in the scene, so every peer has the same config and
## mounts the same outfit locally: no ItemManager instances, no worn_slots mutation
## and no replication are involved. Add this as a child of an Npc and drag ItemType
## clothing resources into the slot fields.
##
## The slot each item wears on comes from the ItemType's own prop_slot; the fields
## below only pick which item (if any) fills each body slot.

@export var torso: ItemType = null
@export var hat: ItemType = null
@export var beard: ItemType = null
@export var glasses: ItemType = null
@export var hand: ItemType = null


func _ready() -> void:
	# Children run _ready before the parent Humanoid, so %PropSystem isn't resolved
	# yet. Defer so the prop system and slot nodes are ready before we mount.
	_apply.call_deferred()


func _apply() -> void:
	var humanoid := get_parent() as Humanoid
	if humanoid == null or humanoid.prop_system == null:
		push_warning("NpcLoadout must be a direct child of a Humanoid")
		return
	var prop_system := humanoid.prop_system
	_mount(prop_system, PropSystem.PropSlot.TORSO, torso)
	_mount(prop_system, PropSystem.PropSlot.HAT, hat)
	_mount(prop_system, PropSystem.PropSlot.BEARD, beard)
	_mount(prop_system, PropSystem.PropSlot.GLASSES, glasses)
	_mount(prop_system, PropSystem.PropSlot.HAND, hand)


func _mount(prop_system: PropSystem, slot: PropSystem.PropSlot, type: ItemType) -> void:
	if type == null:
		return
	if type.prop_slot != slot:
		push_warning(
			"NpcLoadout: '%s' is a %s prop but was set in the %s field"
			% [type.name, PropSystem.PropSlot.keys()[type.prop_slot], PropSystem.PropSlot.keys()[slot]]
		)
		return
	prop_system.mount_visual(type, slot)
