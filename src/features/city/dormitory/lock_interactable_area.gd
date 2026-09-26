extends Interactable

var claimed = false
var door_open = false

@export var door : Node3D

func _ready():
	prompt = "Lock"


func get_prompt(player_id: int) -> String:
	if not claimed:
		return ""
	elif player_id == door.owner_id:
		if door.locked:
			return "Unlock"
		else:
			return "Lock"
	return ""


func can_interact(player_id: int) -> bool:
	if claimed and not door_open and door.owner_id == player_id:
		return true
	return false

func set_open(is_open: bool) -> void:
	door_open = is_open

func claim():
	claimed = true
