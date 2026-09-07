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


func _on_interacted(_player_id: int) -> void:
	# create equip item for it
	var p: Player = PlayerManager.get_local_player_node_or_null()
	if not p.inventory.try_add_item_to_inv(item_id):
		return # no space in inv, abort
	# destroy world item
	_rpc_destroy_world_item.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_destroy_world_item() -> void:
	assert(Net.is_server)
	queue_free()
