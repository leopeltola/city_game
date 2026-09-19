extends ItemWorld



func _ready() -> void:
	super()
	var is_empty = ItemManager.get_item_data(item_id, &"is_empty", true)
	_update_visuals(is_empty)

func _on_interacted(player_id: int) -> void:
	# create equip item for it
	var p: Player = PlayerManager.get_local_player_node_or_null()
	var inv := p.inventory as PlayerInventory
	var item := p.get_equipped_item()
	var is_empty: bool = ItemManager.get_item_data(item_id, &"is_empty") == true
	var is_carrying_pizza: bool = item and item.item_type and item.item_type.name == "pizza"
	var is_cooked_pizza: bool = false
	
	if is_carrying_pizza:
		if ItemManager.get_item_data(item.item_id,&"state") == "cooked":
			is_cooked_pizza = true
	
	if is_carrying_pizza and is_empty and is_cooked_pizza:
		ItemManager.set_and_sync_item_data(item_id, &"is_empty", false)
		_rpc_update_visual.rpc(false)
		var destroyed_item_id := inv.pop_active_item()
		ItemManager.destroy_item(destroyed_item_id)
		return
	elif inv == null or not inv.try_add_item(item_id):
		return # no space in inv, abort
	# Increase Guilt if stealing
	if not has_right_to_pick_up(player_id):
		CrimeManager.add_guilt(player_id, "Stole %s" % type.display_name, 90, 100)
	# destroy world item
	_rpc_destroy_world_item.rpc_id(1)


@rpc("any_peer", "reliable", "call_local")
func _rpc_update_visual(is_empty: bool) -> void:
	_update_visuals(is_empty)


func _update_visuals(is_empty: bool) -> void:
	if is_empty:
		%pizza.hide()
	else:
		%pizza.show()
