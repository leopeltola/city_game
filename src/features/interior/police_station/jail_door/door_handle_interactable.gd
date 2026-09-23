extends Interactable

## While locked the handle can't be used (set by the jail door during a sentence).
var locked := false


func get_prompt(player_id: int) -> String:
	if locked:
		return "Locked"
	return prompt if can_interact(player_id) else "Need Key"


func can_interact(player_id: int) -> bool:
	if locked:
		return false
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if not player or not active:
		return false
	var item := player.get_equipped_item()
	if item and item.item_type and item.item_type.name == "jail_key":
		return true
	return false

func set_open(is_open : bool) -> void:
	if is_open:
		prompt = "Close"
	else:
		prompt = "Open"
