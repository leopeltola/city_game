extends Interactable

var claimed = false
var door_open = false

@export var door : Node3D

var negative_prompt = "Need Cash"

func _ready():
	prompt = "Buy for: " + str(get_parent().get_parent().get_price())


func get_prompt(player_id: int) -> String:
	
	if not claimed and can_interact(player_id):
		return "Buy for: " + str(door.get_price())
	elif not claimed and not can_interact(player_id):
		return "Need Cash"
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
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if not player or not active:
		return false
	var item := player.get_equipped_item()

	if not claimed:
		if item and item.item_type and item.item_type.instance_data.has("money"):
			var item_id = item.item_id
			var cash_amount = ItemManager.get_item_data(item_id, "money", 0)
			var price = door.get_price()

			if cash_amount >= price:
				return true
			else:
				return false
		return false
	else:
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
