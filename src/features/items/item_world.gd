class_name ItemWorld
extends RigidBody3D

@export var type: ItemType = null
@export var interaction_area: Interactable = null
@export var debug_label: Label3D = null

var item_id: int = -1 # -1 is invalid
var launch_force: Vector3 = Vector3.ZERO
var data: Dictionary:
	get:
		return ItemManager.get_item_data_dict_raw(item_id)

var owner_player_id: int = 0 # 0 means owned by no-one
@onready var spawn_stopwatch: Stopwatch = Stopwatch.new()


func _ready() -> void:
	assert(interaction_area)
	assert(interaction_area.get_collision_layer_value(3) == true, "Interactable must have collision layer 3 enabled")
	assert(type)

	interaction_area.prompt = "Pick up %s" % type.display_name
	interaction_area.interacted.connect(_on_interacted)

	if debug_label:
		debug_label.text = "ID %s" % item_id

	if not launch_force.is_zero_approx():
		apply_central_impulse(launch_force)


func get_prompt(player_id: int) -> String:
	if has_right_to_pick_up(player_id):
		return "Pick up %s" % type.display_name
	else:
		return "Steal %s (%ss)" % [type.display_name, roundi(15 - spawn_stopwatch.measure_s())]


func has_right_to_pick_up(player_id: int) -> bool:
	if owner_player_id != 0 and owner_player_id != player_id and spawn_stopwatch.measure_s() < 15:
		return false
	return true


func _on_interacted(player_id: int) -> void:
	# create equip item for it
	var p: Player = PlayerManager.get_local_player_node_or_null()
	var inv := p.inventory as PlayerInventory
	if inv == null or not inv.try_add_item(item_id):
		return # no space in inv, abort
	# Increase Guilt if stealing
	if not has_right_to_pick_up(player_id):
		CrimeManager.add_guilt(player_id, "Stole %s" % type.display_name, 90, 100)
	# destroy world item
	_rpc_destroy_world_item.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_destroy_world_item() -> void:
	assert(Net.is_server)
	queue_free()
