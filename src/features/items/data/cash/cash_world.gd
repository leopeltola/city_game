extends ItemWorld

const bill_colors := [
	Color(0.214, 0.299, 0.33, 1.0),
	Color(0.33, 0.191, 0.275, 1.0),
	Color(0.106, 0.15, 0.33, 1.0),
	Color(0.33, 0.247, 0.175, 1.0),
	Color(0.086, 0.22, 0.171, 1.0),
	Color(0.28, 0.256, 0.098, 1.0),
	Color(0.24, 0.13, 0.25, 1.0),
]

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
	_update()


func _update() -> void:
	var index: int = 6
	var amount: int = ItemManager.get_item_data(item_id, "money", 100)
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


func _on_interacted(player_id: int) -> void:
	# create equip item for it
	var p: Player = PlayerManager.get_local_player_node_or_null()
	var inv := p.inventory as PlayerInventory
	var equipped: ItemEquip = p.get_equipped_item()
	var is_briefcase: bool = equipped and equipped.item_type and equipped.item_type.name == "briefcase"
	var money_amount: int = ItemManager.get_item_data(item_id,"money",0)
	var max_takeable_amount: int = 0
	var should_destroy_world_item: bool = false
	
	if is_briefcase:
		max_takeable_amount = equipped.get_max_to_add()
		if max_takeable_amount <= 0:
			return
		if money_amount > max_takeable_amount:
			print("Money amount is: " , money_amount)
			print("Max takeable amount is: " , max_takeable_amount)
			ItemManager.set_and_sync_item_data(item_id,"money", money_amount - max_takeable_amount)
			equipped.take_money(max_takeable_amount)
		else:
			ItemManager.set_and_sync_item_data(item_id, "money", 0)
			should_destroy_world_item = true
			equipped.take_money(money_amount)
	else:
		if inv == null or not inv.try_add_item(item_id):
			return # no space in inv, abort
		should_destroy_world_item = true
	# Increase Guilt if stealing
	# destroy world item
	if not has_right_to_pick_up(player_id):
		CrimeManager.add_guilt(player_id, "Stole %s" % type.display_name, 90, 100)
	if should_destroy_world_item:
			_rpc_destroy_world_item.rpc_id(1)
