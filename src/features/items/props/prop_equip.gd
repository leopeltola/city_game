class_name PropEquip
extends ItemEquip
## A wearable "prop" item (clothing/accessory). One equip scene serves two states:
##  - held: the equip host mounts it like any item; its HeldAnchor follows the right
##    hand and LMB wears it onto its body slot.
##  - worn: PropSystem mounts it under the matching bone slot; the WornVisual child is
##    shown and the hand anchor is skipped.
##
## The scene must contain a `HeldAnchor` (HandAnchor, right hand) carrying the mesh at
## a held pose, and a `WornVisual` node carrying the mesh at the worn pose relative to
## the body slot.

## True when mounted on a body slot (worn). Set before add_child by PropSystem.
var worn := false


## Worn props may be visual-only (mounted from an ItemType with no item id); held props
## still require a valid ItemManager item id.
func _validate() -> void:
	assert(player, "ItemEquip requires player to be set before it is added to the tree")
	assert(item_type, "Prop equips require item_type")
	if not worn:
		assert(item_id != -1, "Held prop equips require a valid item_id")


func _on_equipped() -> void:
	_apply_presentation()
	if not worn:
		super()


func _on_unequipped() -> void:
	if not worn:
		super()


func _apply_presentation() -> void:
	var held := get_node_or_null("HeldAnchor")
	var worn_visual := get_node_or_null("WornVisual")
	if held is Node3D:
		held.visible = not worn
	if worn_visual is Node3D:
		worn_visual.visible = worn


func _unhandled_input(event: InputEvent) -> void:
	if worn or not player.is_local or player.is_action_locked() \
			or (HUD.instance and HUD.instance.is_blocking_input()):
		return
	if event.is_action_pressed("left_click"):
		var inv := player.inventory as PlayerInventory
		if inv != null:
			inv.wear_item(item_id)
			var vp := get_viewport()
			if vp:
				vp.set_input_as_handled()
