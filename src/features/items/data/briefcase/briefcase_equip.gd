extends ItemEquip

const MAX_MONEY: int = 1000


# Called when the node enters the scene tree for the first time.
func _ready():
	super()


func take_money(added_amount):
	var money_amount = ItemManager.get_item_data(item_id, "money", 0)
	ItemManager.set_and_sync_item_data(item_id, "money", money_amount + added_amount)
	print("Briefcase money: ", ItemManager.get_item_data(item_id, "money", -1))


func get_current_money() -> int:
	return ItemManager.get_item_data(item_id, "money", 0)


func get_max_to_add() -> int:
	return maxi(0, MAX_MONEY - get_current_money())
