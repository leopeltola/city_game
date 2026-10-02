class_name ItemWorld
extends RigidBody3D
## An item lying in the world that a player can pick up (or steal during the owner's
## grace window). Subclasses hook [method _handle_use] to consume/transform the item
## instead of pocketing it (a briefcase scooping cash, sauce onto a pizza).

@export var type: ItemType = null
@export var interaction_area: Interactable = null
@export var debug_label: Label3D = null

## Owner id for items dropped by an NPC (which has no player id). Any player who loots
## one within the ownership grace window counts as stealing.
const NPC_OWNER_ID := -1

## How long the original owner's pickup is protected after the item enters the world.
const OWNERSHIP_GRACE_S := 15.0

## Scale multiplier the visual starts at when a world item pops into being.
const SPAWN_INTRO_SCALE := 0.35
## Duration of the spawn pop-in tween.
const SPAWN_INTRO_TIME := 0.25
## Duration of the shrink-out tween played before the item is freed.
const DESPAWN_TIME := 0.15
## Target scale for the shrink-out; not exactly zero to avoid a singular basis for a frame.
const DESPAWN_END_SCALE := Vector3(0.001, 0.001, 0.001)

var item_id: int = -1 # -1 is invalid
var launch_force: Vector3 = Vector3.ZERO
var owner_player_id: int = 0 # 0 means owned by no-one
@onready var spawn_stopwatch: Stopwatch = Stopwatch.new()

## In-flight spawn intro, killed if the item is despawned mid-animation.
var _intro_tween: Tween = null


func _ready() -> void:
	assert(interaction_area)
	assert(interaction_area.get_collision_layer_value(3) == true, "Interactable must have collision layer 3 enabled")
	assert(type)

	interaction_area.prompt = "Pick up %s" % type.display_name
	interaction_area.interacted.connect(_on_interacted)

	# Toggle collision layers
	set_collision_layer_value(3, true) # mark as interaction
	set_collision_layer_value(4, true) # mark as item
	set_collision_mask_value(1, true) # col with environment
	set_collision_mask_value(4, true) # col with items
	set_collision_mask_value(7, true) # col with road

	if debug_label:
		debug_label.text = "ID %s" % item_id

	if not launch_force.is_zero_approx():
		apply_central_impulse(launch_force)

	_play_spawn_intro()


## Pops the visual into being: starts small and overshoots back to full scale. Only the
## visual children are scaled, so collision shapes and launch physics stay untouched.
func _play_spawn_intro() -> void:
	if _intro_tween:
		_intro_tween.kill()
	_intro_tween = create_tween().set_parallel(true)
	for visual: Node3D in _get_visual_nodes():
		var target: Vector3 = visual.scale
		visual.scale = target * SPAWN_INTRO_SCALE
		_intro_tween.tween_property(visual, "scale", target, SPAWN_INTRO_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Shrinks the visual out of existence, then frees this node. Used on pickup/consumption so
## an item doesn't just blink away. Runs on every peer via the destroy RPCs.
func play_despawn() -> void:
	if _intro_tween:
		_intro_tween.kill()
		_intro_tween = null
	if interaction_area:
		interaction_area.active = false
	freeze = true
	var tween := create_tween().set_parallel(true)
	for visual: Node3D in _get_visual_nodes():
		tween.tween_property(visual, "scale", DESPAWN_END_SCALE, DESPAWN_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)


## Direct children that carry the item's visuals (the .glb instance and any debug mesh),
## i.e. Node3Ds that are not collision shapes, collision objects or labels.
func _get_visual_nodes() -> Array[Node3D]:
	var visuals: Array[Node3D] = []
	for child: Node in get_children():
		var visual := child as Node3D
		if visual == null or child is CollisionShape3D \
				or child is CollisionObject3D or child is Label3D:
			continue
		visuals.append(visual)
	return visuals


func get_prompt(player_id: int) -> String:
	if has_right_to_pick_up(player_id):
		return "Pick up %s" % type.display_name
	return _steal_prompt()


## Text shown while the owner's pickup grace window is still active.
func _steal_prompt() -> String:
	var remaining := maxi(0, roundi(OWNERSHIP_GRACE_S - spawn_stopwatch.measure_s()))
	return "Steal %s (%ss)" % [type.display_name, remaining]


func has_right_to_pick_up(player_id: int) -> bool:
	if owner_player_id != 0 and owner_player_id != player_id \
			and spawn_stopwatch.measure_s() < OWNERSHIP_GRACE_S:
		return false
	return true


func _on_interacted(player_id: int) -> void:
	var inventory := _interactor_inventory(player_id)
	if inventory == null:
		return
	# A use-transform (sauce, briefcase scoop, ...) consumes the item itself.
	if _handle_use(player_id, inventory):
		return

	if not inventory.try_add_item(item_id):
		return # no space in inv, abort
	if not has_right_to_pick_up(player_id):
		CrimeManager.add_guilt(player_id, "Stole %s" % type.display_name, 90, _theft_guilt())
	_rpc_destroy_world_item.rpc_id(1)


## Virtual: consume/use this item without pocketing it (pour sauce, fill a briefcase).
## Return true when the interaction is fully handled and [method _on_interacted] should
## stop, so the item is neither pocketed nor destroyed by the base path.
func _handle_use(_player_id: int, _inventory: PlayerInventory) -> bool:
	return false


## Guilt (€) added when this item is stolen: the flat 100€ crime cost, plus any money
## the item itself carries.
func _theft_guilt() -> int:
	return 100 + int(ItemManager.get_item_data(item_id, "money", 0))


## The inventory of the acting player, or null when the actor can't hold items.
func _interactor_inventory(player_id: int) -> PlayerInventory:
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if player == null:
		return null
	return player.inventory


## The item currently equipped by the acting player, or null.
func _interactor_equipped(player_id: int) -> ItemEquip:
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	return player.get_equipped_item() if player != null else null


## Client asks the server to remove this world node (the item's data survives - it was
## picked up / consumed into an inventory or another item).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_destroy_world_item() -> void:
	assert(Net.is_server)
	_rpc_apply_destroy_world_item.rpc()


## Server tells every peer to play the despawn, so the item shrinks out everywhere.
@rpc("authority", "call_local", "reliable")
func _rpc_apply_destroy_world_item() -> void:
	play_despawn()
