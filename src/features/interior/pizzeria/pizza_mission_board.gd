class_name PizzaMissionBoard
extends Interactable
## Assigns a delivery note to the pizza box a player is holding: a random registered
## [MissionLocation] plus a cash reward. One destination per box; already-noted boxes are
## ignored, so interacting again cannot reroll a note.

@export var reward_min := 70
@export var reward_max := 150


func get_prompt(player_id: int) -> String:
	return prompt if can_interact(player_id) else ""


func can_interact(player_id: int) -> bool:
	return active and _assignable_box_id(player_id) != -1


func interact(player_id: int) -> void:
	assign(player_id)


## Writes a random location and reward onto the held box's note.
func assign(player_id: int) -> void:
	var box_id := _assignable_box_id(player_id)
	if box_id == -1:
		return
	var locations := MissionLocation.get_all()
	if locations.is_empty():
		return
	var location: MissionLocation = locations.pick_random()
	ItemManager.set_and_sync_item_data(box_id, &"location", location.location_name)
	ItemManager.set_and_sync_item_data(box_id, &"reward", randi_range(reward_min, reward_max))


# Returns the held pizza box's id when it is non-empty and has no note yet, else -1.
func _assignable_box_id(player_id: int) -> int:
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if player == null:
		return -1
	var item := player.get_equipped_item()
	if item == null or item.item_type == null or item.item_type.name != "pizza_box":
		return -1
	if ItemManager.get_item_data(item.item_id, &"is_empty", true) == true:
		return -1
	if ItemManager.get_item_data(item.item_id, &"location", &"") != &"":
		return -1
	return item.item_id
