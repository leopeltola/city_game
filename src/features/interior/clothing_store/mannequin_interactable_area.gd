extends Interactable

func _ready():
	prompt = "Buy for: " + str(get_parent().get_price())


func get_prompt(player_id: int) -> String:
	return prompt if can_interact(player_id) else "Need %d€" % get_parent().get_price()


func can_interact(player_id: int) -> bool:
	if not active:
		return false
	return MoneyManager.can_pay(player_id, get_parent().get_price())
