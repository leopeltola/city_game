extends ItemEquip

func _ready() -> void:
	super()

	_update()


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	var amount: int = ItemManager.get_item_data(item_id, "money", 0)
	CashVisual.apply($RightHandAnchor/cash/CashArmature/Skeleton3D/Cash, amount)
