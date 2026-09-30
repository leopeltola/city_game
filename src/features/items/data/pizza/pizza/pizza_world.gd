extends ItemWorld

class_name PizzaWorld

# Pizza states: empty, filled, cooked

func _ready() -> void:
	super()
	var current_state = ItemManager.get_item_data(item_id, &"state", "empty")
	_update_visuals(current_state)


func get_prompt(player_id: int) -> String:
	var item := _interactor_equipped(player_id)
	var is_carrying_pizza_sauce: bool = item and item.item_type and item.item_type.name == "pizza_sauce"
	if is_carrying_pizza_sauce:
		return "Add Pizza Sauce"
	return super.get_prompt(player_id)


## Pouring sauce fills the pizza instead of pocketing it.
func _handle_use(player_id: int, inventory: PlayerInventory) -> bool:
	var item := _interactor_equipped(player_id)
	var is_carrying_pizza_sauce: bool = item and item.item_type and item.item_type.name == "pizza_sauce"
	var is_empty: bool = ItemManager.get_item_data(item_id, &"state") == "empty"
	if not (is_carrying_pizza_sauce and is_empty):
		return false

	ItemManager.set_and_sync_item_data(item_id, &"state", "filled")
	_rpc_update_visual.rpc("filled")
	var destroyed_item_id := inventory.pop_active_item()
	ItemManager.destroy_item(destroyed_item_id)
	return true


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
