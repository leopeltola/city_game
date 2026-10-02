class_name ShopMannequin
extends Node3D

const CASH_SFX: AudioStream = preload("res://assets/sfx/slot_machine/cash_register.ogg")

@export var shown_item: ItemType
@export var price: int = 100
@export var item_container: Node3D
@export var hide_mannequin_body: bool = false


func _ready() -> void:
	%MannequinInteractableArea.interacted.connect(_on_interacted)
	
	if shown_item and item_container:
		var item_instance = shown_item.get_display_item_scene().instantiate()
		item_container.add_child(item_instance)
		
		if hide_mannequin_body and has_node("mannequin/Mannequinbody"):
			$mannequin/Mannequinbody.hide()


func _on_interacted(player_id: int) -> void:
	var label := "Purchase"
	if shown_item:
		label = "Bought %s" % shown_item.display_name
	if not MoneyManager.pay(player_id, price, label):
		return

	Audio.play_sfx_3d(CASH_SFX, global_position, -6.0, 25.0, true)
	spawn_item()


func get_price() -> int:
	return price


func spawn_item() -> void:
	if Net.is_client:
		_rpc_spawn_item.rpc_id(1)
	elif Net.is_server:
		_rpc_spawn_item()


@rpc("any_peer", "reliable", "call_remote")
func _rpc_spawn_item() -> void:
	assert(Net.is_server)
	var item_name = shown_item.name
	var id: int = ItemManager.create_item_of_type(item_name)
	ItemManager.create_world_item_for(
		id,
		%ItemSpawnPos.global_position,
		%ItemSpawnPos.global_rotation,
		Vector3.ZERO,
	)
