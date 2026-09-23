extends Interactable

func get_prompt(player_id: int) -> String:
	return "Insert Cash" if can_interact(player_id) else "Need Cash"


func interact(player_id: int) -> void:
	interacted.emit(player_id)


func can_interact(player_id: int) -> bool:
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if not player or not active:
		return false
	var item := player.get_equipped_item()
	if item and item.item_type and item.item_type.instance_data.has("money"):
		return true
	return false
