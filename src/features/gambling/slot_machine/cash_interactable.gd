extends Interactable

func get_prompt(player_id: int) -> String:
	return prompt if can_interact(player_id) else "Need Cash"


func interact(player_id: int) -> void:
	print("Player put money in!")
	interacted.emit(player_id)


func can_interact(player_id: int) -> bool:
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if not player or not active:
		return false
	if player.get_equipped_item() and player.get_equipped_item().item_type.name == "cash":
		return true
	return false
