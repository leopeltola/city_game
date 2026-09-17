extends ItemEquip


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super()
	var current_state = ItemManager.get_item_data(item_id, &"state", "empty")
	_update_visuals(current_state)


@rpc("any_peer", "reliable", "call_local")
func _rpc_update_visual(new_state) -> void:
	_update_visuals(new_state)


func _update_visuals(state) -> void:
	match state:
		"empty":
			%pizza_ingredients.hide()
		"filled":
			%pizza_ingredients.show()
		"cooked":
			%pizza_ingredients.show()
