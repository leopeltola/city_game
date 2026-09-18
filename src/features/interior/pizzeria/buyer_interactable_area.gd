extends Interactable



func get_prompt(player_id: int) -> String:
	return prompt if can_interact(player_id) else ""


func can_interact(player_id: int) -> bool:
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if not player or not active:
		return false
	var inv := player.inventory as PlayerInventory
	var item := player.get_equipped_item()
	var item_id : int = item.item_id
	var is_carrying_pizza_box: bool = item and item.item_type and item.item_type.name == "pizza_box"
	var is_empty: bool = ItemManager.get_item_data(item_id, &"is_empty") == true
	if not is_carrying_pizza_box or is_empty:
		return false

	return true
