extends Interactable


func get_prompt(player_id: int) -> String:
	return prompt if can_interact(player_id) else "Need filled Pizza"


func can_interact(player_id: int) -> bool:
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if not player or not active:
		return false
	var item := player.get_equipped_item()
	if item and item.item_type and item.item_type.name == "pizza":
		print(ItemManager.get_item_data(item.item_id,&"state","empty"))
		if ItemManager.get_item_data(item.item_id,&"state","empty") == "filled":
			return true
		else:
			return false
	return false
