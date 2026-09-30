extends Interactable

var claimed = false
var door_open = false

@export var door : Node3D

var negative_prompt = "Need cash"

func _ready():
	prompt = "Buy for: " + str(get_parent().get_parent().get_price())


func get_prompt(player_id: int) -> String:
	
	if not claimed and can_interact(player_id):
		return "Buy for: " + str(door.get_price())
	elif not claimed and not can_interact(player_id):
		return "Need %d€" % door.get_price()
	if claimed and door.locked:
		return "Door locked"
	if claimed and can_interact(player_id):
		if door.locked:
			return "Door locked"
		elif door_open:
			return "Close"
		else:
			return "Open"
	
	return prompt if can_interact(player_id) else negative_prompt


func can_interact(player_id: int) -> bool:
	if not active:
		return false
	if not claimed:
		return MoneyManager.can_pay(player_id, door.get_price())
	return true

func set_open(is_open: bool) -> void:
	door_open = is_open
	
	if door_open:
		prompt = "Close"
	else:
		prompt = "Open"

func claim():
	claimed = true
	prompt = "Open"
