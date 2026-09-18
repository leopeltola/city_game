extends Node3D


var is_cooking = false



func _ready():
	%OvenInteractableArea.interacted.connect(_on_interacted)


func _on_interacted(player_id: int) -> void:
	var p: Player = PlayerManager.get_local_player_node_or_null()
	var inv := p.inventory as PlayerInventory
	var destroyed_item_id := inv.pop_active_item()
	ItemManager.destroy_item(destroyed_item_id)
	cook_pizza()



func cook_pizza() -> void:
	if Net.is_client:
		_rpc_cook_pizza.rpc_id(1)
	elif Net.is_server:
		_rpc_cook_pizza()


@rpc("any_peer", "reliable", "call_remote")
func _rpc_cook_pizza() -> void:
	if not is_cooking:
		is_cooking = true
		%PizzaTimer.start()
		_rpc_sync_cooking.rpc()

@rpc("authority","reliable","call_local")
func _rpc_sync_cooking():
	is_cooking = true
	%AnimationPlayer.play("close")
	%pizza.show()

@rpc("authority","reliable","call_local")
func _rpc_on_pizza_cooked():
	is_cooking = false
	%pizza.hide()
	%AnimationPlayer.play_backwards("close")



func _on_timer_timeout():
	_rpc_on_pizza_cooked.rpc()
	var id: int = ItemManager.create_item_of_type("pizza", { &"state": "cooked" })
	ItemManager.create_world_item_for(id, %PizzaSpawnPos.global_position, %PizzaSpawnPos.global_rotation, Vector3.ZERO)
