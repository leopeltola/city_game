extends ItemEquip


func _ready() -> void:
	super()
	var is_empty = ItemManager.get_item_data(item_id, &"is_empty", true)
	_update_visuals(is_empty)


func _update_visuals(is_empty: bool) -> void:
	if is_empty:
		%pizza.hide()
	else:
		%pizza.show()
