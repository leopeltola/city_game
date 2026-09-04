extends ItemEquip

func _ready() -> void:
	super()

	$cash/CashArmature/Skeleton3D/Cash.set_instance_shader_parameter("bill_amount", ItemManager.get_item_data(item_id, "amount", 100))


func _process(delta: float) -> void:
	$cash/CashArmature/Skeleton3D/Cash.set_instance_shader_parameter("bill_amount", ItemManager.get_item_data(item_id, "amount", 100))
