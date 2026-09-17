extends Interactable



func get_prompt(player_id: int) -> String:
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if not player or not active:
		return "No can do"
	var item := player.get_equipped_item()
	if item and item.item_type and item.item_type.name == "pizza_sauce":
		return "Add %s" % item.item_type.display_name
	elif item and item.item_type:
		return "Pick up %s" % item.item_type.display_name
	return prompt if can_interact(player_id) else "Need Key"
