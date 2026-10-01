extends ItemWorld


func _ready() -> void:
	super()
	var is_empty = ItemManager.get_item_data(item_id, &"is_empty", true)
	_update_visuals(is_empty)
	_update_note()
	ItemManager.item_data_changed.connect(_on_item_data_changed)


# The note is written by the mission board while the box is held, so the label has to
# react to live item data rather than only reading it once on spawn.
func _on_item_data_changed(changed_id: int, key: StringName) -> void:
	if changed_id == item_id and (key == &"location" or key == &"reward"):
		_update_note()


func _update_note() -> void:
	var location: StringName = ItemManager.get_item_data(item_id, &"location", &"")
	if location == &"":
		%NoteLabel.hide()
		return
	var reward := int(ItemManager.get_item_data(item_id, &"reward", 0))
	%NoteLabel.text = "%s — %d€" % [String(location), reward]
	%NoteLabel.show()


## Packing a cooked pizza into the box fills it instead of pocketing it.
func _handle_use(player_id: int, inventory: PlayerInventory) -> bool:
	var item := _interactor_equipped(player_id)
	var is_carrying_pizza: bool = item and item.item_type and item.item_type.name == "pizza"
	var is_empty: bool = ItemManager.get_item_data(item_id, &"is_empty") == true

	var is_cooked_pizza := false
	if is_carrying_pizza:
		is_cooked_pizza = ItemManager.get_item_data(item.item_id, &"state") == "cooked"

	if not (is_carrying_pizza and is_empty and is_cooked_pizza):
		return false

	ItemManager.set_and_sync_item_data(item_id, &"is_empty", false)
	_rpc_update_visual.rpc(false)
	var destroyed_item_id := inventory.pop_active_item()
	ItemManager.destroy_item(destroyed_item_id)
	return true


@rpc("any_peer", "reliable", "call_local")
func _rpc_update_visual(is_empty: bool) -> void:
	_update_visuals(is_empty)


func _update_visuals(is_empty: bool) -> void:
	if is_empty:
		%pizza.hide()
	else:
		%pizza.show()
