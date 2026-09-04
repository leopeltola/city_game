extends ItemWorld

var _last_bill_amount: int = -1


func _ready() -> void:
	super()

	_update_bill_amount()


func _process(_delta: float) -> void:
	_update_bill_amount()


func _update_bill_amount() -> void:
	var amount: int = ItemManager.get_item_data(item_id, "amount", 0)
	if amount == _last_bill_amount:
		return
	_last_bill_amount = amount
	$cash/CashArmature/Skeleton3D/Cash.set_instance_shader_parameter("bill_amount", amount)
