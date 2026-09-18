extends Interactable


func get_prompt(player_id: int) -> String:
	return prompt if can_interact(player_id) else ""


func can_interact(player_id: int) -> bool:
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if not player or not active:
		return false
	return true
