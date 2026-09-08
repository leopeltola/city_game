extends ItemEquip

const bill_colors := [
	Color(0.214, 0.299, 0.33, 1.0),
	Color(0.33, 0.191, 0.275, 1.0),
	Color(0.106, 0.15, 0.33, 1.0),
	Color(0.33, 0.247, 0.175, 1.0),
	Color(0.086, 0.22, 0.171, 1.0),
	Color(0.28, 0.256, 0.098, 1.0),
	Color(0.24, 0.13, 0.25, 1.0),
]


func _ready() -> void:
	super()

	_update()


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	var index: int = 6
	var amount: int = ItemManager.get_item_data(item_id, "amount", 0)
	if amount < 10:
		index = 0 # 5
	elif amount < 20:
		index = 1 # 10
	elif amount < 50:
		index = 2 # 20
	elif amount < 100:
		index = 3 # 50
	elif amount < 200:
		index = 4 # 100
	elif amount < 500:
		index = 5 # 200
	$cash/CashArmature/Skeleton3D/Cash.set_instance_shader_parameter("bill_amount", amount)
	$cash/CashArmature/Skeleton3D/Cash.set_instance_shader_parameter("texture_index", index)
	$cash/CashArmature/Skeleton3D/Cash.set_instance_shader_parameter("text_color", bill_colors[index])
