extends Interactable
## Handle for a jail cell door. A jail key can only OPEN the door, never close it, so
## the handle is only usable while the door is closed.

## Tracks the door state so the prompt can reflect it.
var door_open := true


func get_prompt(player_id: int) -> String:
	if door_open:
		return ""
	return "Open" if can_interact(player_id) else "Needs key"


func can_interact(player_id: int) -> bool:
	if door_open or not active:
		return false
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if not player:
		return false
	return player.has_item_of_type_equipped("jail_key")


func set_open(is_open: bool) -> void:
	door_open = is_open
