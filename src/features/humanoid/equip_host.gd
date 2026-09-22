class_name EquipHost
extends Node
## Shared equip mounting for actors (players with a full inventory, NPCs with fixed
## gear). Holds the neutral %EquipRoot and the hand slots, mounts/unmounts the current
## ItemEquip (or the unarmed fists when no item is held) and reports the equipped
## idle-animation override to the ActorAnimator.
##
## This is a local, derived view: every peer rebuilds the mounted node from replicated
## state (the inventory's active slot, or the camera toggle), so nothing here is
## replicated or sent over RPC directly. Players drive mount_active()/toggle_camera()
## through PlayerInventory; NPCs call mount_unarmed() for their fixed gear.
##
## The camera is special unarmed gear with no backing slot: while it is out the active
## slot's item stays stowed and is re-mounted when the camera is lowered.

## Mounted when no item is equipped so the actor can always fight (bare fists).
## Unlike real items this is unarmed "gear": no ItemType, no ItemManager instance id.
const UNARMED_EQUIP_SCENE: PackedScene = preload("res://src/features/items/data/fists/fists_equip.tscn")

## Camera gear toggled with the "camera" action.
const CAMERA_EQUIP_SCENE: PackedScene = preload("res://src/features/items/data/camera/camera_equip.tscn")

## The actor this host belongs to. Equips reach the actor's animator/status through it.
@export var player: Humanoid = null
## Neutral mount that the whole equip scene parents under (stays put). Per-hand
## content inside the equip is driven to the hand slots via HandAnchors instead.
@export var _equip_root: Node3D = null
## Hand bone slots the HandAnchors get their transforms pushed from.
@export var _right_equip_slot: Node3D = null
@export var _left_equip_slot: Node3D = null

## True while the camera is out. Replicated on players; the setter keeps the mounted
## visual in sync on every peer. While up, the active slot's item stays stowed and is
## re-mounted when lowered.
@export var camera_out := false:
	set(value):
		var changed := camera_out != value
		camera_out = value
		if changed and is_inside_tree():
			if camera_out:
				mount_camera()
			else:
				mount_active()

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


## True while the camera gear is mounted.
func is_camera_out() -> bool:
	return camera_out


## Toggles the camera gear in/out. Mounting is handled by the camera_out setter.
func toggle_camera() -> void:
	camera_out = not camera_out


## Lowers the camera (re-mounting the active slot's item) if it is currently out.
func lower_camera() -> void:
	if camera_out:
		camera_out = false


## Mounts the item held in the owner's active inventory slot, or the unarmed fists when
## the slot is empty. Runs on every peer (from replicated inventory setters too), so it
## tolerates a missing/short inventory instead of asserting.
func mount_active() -> void:
	if camera_out:
		# Camera is up; slot changes are UI-only until it comes down.
		return
	if _equip_root == null:
		return

	var inventory: Node = player.inventory if is_instance_valid(player) else null
	var item_id: int = inventory.get_active_item_id() if inventory != null else -1

	_remove_equipped_node()
	if item_id == -1:
		mount_unarmed()
		return

	# The item may have been destroyed (e.g. full cash insert into the slot machine)
	# while a stale slot snapshot is still being replicated. Guard against it so we
	# never hand a nil type name to get_item_type().
	var item_data := ItemManager.get_item_data_dict_raw(item_id)
	if item_data.is_empty():
		push_error("Tried equipping item but item_id not found: ID: %s\nitem_data: %s" % [item_id, item_data])
		if inventory != null:
			inventory.clear_stale_active(item_id)
		mount_unarmed()
		return

	var type: ItemType = ItemManager.get_item_type(item_data["type"])
	var equipped_item: ItemEquip = type.get_equip_item_scene().instantiate()

	equipped_item.item_id = item_id
	equipped_item.interact_ray = %InteractRay
	equipped_item.player = player
	_equipped_node = equipped_item

	_equip_root.add_child(equipped_item)


## Mounts the camera gear, replacing the current equip. Lowering re-mounts the
## active slot's item (or fists) through the camera_out setter.
func mount_camera() -> void:
	if _equip_root == null:
		return
	_remove_equipped_node()
	var camera: ItemEquip = CAMERA_EQUIP_SCENE.instantiate()
	camera.player = player
	camera.interact_ray = %InteractRay
	_equipped_node = camera
	_equip_root.add_child(camera)


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
