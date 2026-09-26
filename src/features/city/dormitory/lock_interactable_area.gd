extends Interactable

var claimed = false
var door_open = false

@export var door : Node3D

func _ready():
	prompt = "Lock"


func get_prompt(player_id: int) -> String:
	if not claimed:
		return "Property not owned"
	elif player_id == door.owner_id:
		if door.locked:
			return "Unlock"
		else:
			return "Lock"
	elif player_id != door.owner_id:
		if door.locked:
			var p: Player = PlayerManager.get_local_player_node_or_null()
			var inv := p.inventory as PlayerInventory
			var item := p.get_equipped_item()
			if item and item.item_type and item.item_type.name == "lock_pick_set":
				return "Lockpick"
		else:
			return "..."
	
	return "..."


func can_interact(player_id: int) -> bool:
	if claimed and not door_open and door.owner_id == player_id:
		return true
	elif claimed and not door_open:
		var p: Player = PlayerManager.get_local_player_node_or_null()
		var inv := p.inventory as PlayerInventory
		var item := p.get_equipped_item()
		if item and item.item_type and item.item_type.name == "lock_pick_set":
			return true
	return false

func set_open(is_open: bool) -> void:
	door_open = is_open

func claim():
	claimed = true
