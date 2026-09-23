extends Interactable
## Police station front desk. A player submits a photo of a suspect here: the photo's
## identifiability is rolled and, if it passes, the guilt snapshotted on the photo is
## added to the subject's bounty (making them wanted). The photo is always consumed.

func get_prompt(player_id: int) -> String:
	return prompt if can_interact(player_id) else "No photo to submit"


func can_interact(player_id: int) -> bool:
	if not active:
		return false
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if player == null or player.inventory == null:
		return false
	return _held_photo_id(player) != -1


## Returns the item id of the photo currently held in the active slot, or -1 if not a photo.
func _held_photo_id(player: Player) -> int:
	if player.equipment != null and player.equipment.is_camera_out():
		return -1
	var item_id: int = player.inventory.get_active_item_id()
	if item_id == -1:
		return -1
	if StringName(ItemManager.get_item_data(item_id, "type")) != &"photo":
		return -1
	return item_id


func interact(player_id: int) -> void:
	if Net.is_server:
		_submit(player_id)
	elif Net.is_client:
		_rpc_submit_photo.rpc_id(1, player_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_submit_photo(player_id: int) -> void:
	assert(Net.is_server)
	_submit(player_id)


func _submit(player_id: int) -> void:
	assert(Net.is_server)
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if player == null or player.inventory == null:
		return

	var photo_id: int = _held_photo_id(player)
	if photo_id == -1:
		return

	var subject_id: int = ItemManager.get_item_data(photo_id, "subject_player_id", 0)
	var guilt: int = ItemManager.get_item_data(photo_id, "guilt", 0)
	var identifiability: int = ItemManager.get_item_data(photo_id, "identifiability", 0)

	var accepted := false
	if subject_id != 0 and subject_id != player_id and guilt > 0:
		accepted = randf() * 100.0 <= float(identifiability)
	if accepted:
		CrimeManager.set_bounty(
			subject_id,
			CrimeManager.get_player_bounty(subject_id) + guilt,
		)

	var pd: PlayerData = PlayerManager.get_player_by_id(player_id)
	if pd == null:
		return

	_rpc_consume_photo.rpc_id(pd.peer_id, photo_id)

	if accepted:
		MessageManager.send_message_to(
			player_id,
			"Police Department",
			"Evidence Accepted",
			"The photo was clear enough to identify the suspect. %s€ has been added to their bounty." % guilt,
		)
	else:
		MessageManager.send_message_to(
			player_id,
			"Police Department",
			"Evidence Rejected",
			"The photo could not be used to identify a suspect.",
		)


@rpc("authority", "call_remote", "reliable")
func _rpc_consume_photo(photo_id: int) -> void:
	var player: Player = PlayerManager.get_local_player_node_or_null()
	if player != null and player.inventory != null:
		player.inventory.remove_item(photo_id)
		ItemManager.destroy_item(photo_id)
