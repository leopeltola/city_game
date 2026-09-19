extends ItemWorld

class_name PizzaWorld

# Pizza states: empty, filled, cooked

func _ready() -> void:
	super()
	var current_state = ItemManager.get_item_data(item_id, &"state", "empty")
	_update_visuals(current_state)


func get_prompt(player_id: int) -> String:
	var p: Player = PlayerManager.get_local_player_node_or_null()
	var item := p.get_equipped_item()
	var is_carrying_pizza_sauce: bool = item and item.item_type and item.item_type.name == "pizza_sauce"
	if is_carrying_pizza_sauce:
		return "Add Pizza Sauce"
	elif has_right_to_pick_up(player_id):
		return "Steal %s (%ss)" % [type.display_name, roundi(15 - spawn_stopwatch.measure_s())]
	else:
		return "Pick up %s" % type.display_name


func _on_interacted(player_id: int) -> void:
	# create equip item for it
	var p: Player = PlayerManager.get_local_player_node_or_null()
	var inv := p.inventory as PlayerInventory
	var item := p.get_equipped_item()
	var is_empty: bool = ItemManager.get_item_data(item_id, &"state") == "empty"
	var is_carrying_pizza_sauce: bool = item and item.item_type and item.item_type.name == "pizza_sauce"
	
	if is_carrying_pizza_sauce and is_empty:
		ItemManager.set_and_sync_item_data(item_id, &"state", "filled")
		_rpc_update_visual.rpc("filled")
		var destroyed_item_id := inv.pop_active_item()
		ItemManager.destroy_item(destroyed_item_id)
		return
	elif inv == null or not inv.try_add_item(item_id):
		return # no space in inv, abort
	# Increase Guilt if stealing
	if not has_right_to_pick_up(player_id):
		CrimeManager.add_guilt(player_id, "Stole %s" % type.display_name, 90, 100)
	# destroy world item
	_rpc_destroy_world_item.rpc_id(1)


@rpc("any_peer", "reliable", "call_local")
func _rpc_update_visual(new_state) -> void:
	_update_visuals(new_state)


func _update_visuals(state) -> void:
	match state:
		"empty":
			%pizza_ingredients.hide()
		"filled":
			%pizza_ingredients.show()
		"cooked":
			%pizza_ingredients.show()
