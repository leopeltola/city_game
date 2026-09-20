extends Interactable

func _ready():
	prompt = "Buy for: " + str(get_parent().get_price())


func get_prompt(player_id: int) -> String:
	return prompt if can_interact(player_id) else "Need Cash"


func can_interact(player_id: int) -> bool:
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if not player or not active:
		return false
	var item := player.get_equipped_item()
	if item and item.item_type and item.item_type.instance_data.has("money"):
		var item_id = item.item_id
		var cash_amount = ItemManager.get_item_data(item_id, "money", 0)
		var price = get_parent().get_price()

		if cash_amount >= price:
			return true
		else:
			return false
	return false


func set_open(is_open: bool) -> void:
	if is_open:
		prompt = "Close"
	else:
		prompt = "Open"
