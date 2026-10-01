extends ItemEquip


func _ready() -> void:
	super()
	var is_empty = ItemManager.get_item_data(item_id, &"is_empty", true)
	_update_visuals(is_empty)

	_update_note()
	ItemManager.item_data_changed.connect(_on_item_data_changed)


func _on_unequipped() -> void:
	super()
	if ItemManager.item_data_changed.is_connected(_on_item_data_changed):
		ItemManager.item_data_changed.disconnect(_on_item_data_changed)


# The note is written by the mission board while this box is held, so the label reacts to
# live item data instead of only reading it once.
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


func _update_visuals(is_empty: bool) -> void:
	if is_empty:
		%pizza.hide()
	else:
		%pizza.show()
