extends ItemWorld

var _last_bill_amount: int = -1


func _ready() -> void:
	super()
	_update_bill_amount()


func _process(_delta: float) -> void:
	_update_bill_amount()


func _update_bill_amount() -> void:
	var amount: int = ItemManager.get_item_data(item_id, "money", 0)
	if amount == _last_bill_amount:
		return
	_last_bill_amount = amount
	CashVisual.apply($cash/CashArmature/Skeleton3D/Cash, amount)


## A held briefcase scoops the cash directly into itself instead of pocketing the stack.
func _handle_use(player_id: int, _inventory: PlayerInventory) -> bool:
	var equipped: ItemEquip = _interactor_equipped(player_id)
	var is_briefcase: bool = equipped and equipped.item_type and equipped.item_type.name == "briefcase"
	if not is_briefcase:
		return false

	var max_takeable: int = equipped.get_max_to_add()
	if max_takeable <= 0:
		return true

	var money_amount: int = ItemManager.get_item_data(item_id, "money", 0)
	var stolen: int
	if money_amount > max_takeable:
		ItemManager.set_and_sync_item_data(item_id, "money", money_amount - max_takeable)
		equipped.take_money(max_takeable)
		stolen = max_takeable
	else:
		ItemManager.set_and_sync_item_data(item_id, "money", 0)
		equipped.take_money(money_amount)
		stolen = money_amount
		_rpc_destroy_world_item.rpc_id(1)

	if not has_right_to_pick_up(player_id):
		CrimeManager.add_guilt(player_id, "Stole %s" % type.display_name, 90, 100 + stolen)
	return true


## A plain cash stack is worth only its money when stolen (no flat 100€ on top).
func _theft_guilt() -> int:
	return int(ItemManager.get_item_data(item_id, "money", 0))
