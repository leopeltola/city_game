extends ItemEquip

const MAX_MONEY: int = 50000
@export var inspect_animation := ""

var inspecting : bool = false

var _last_display_money: int = -1

# Called when the node enters the scene tree for the first time.
func _ready():
	super()
	close_top()


func _process(_delta: float) -> void:
	if inspecting:
		_refresh_money_display()


func _unhandled_input(event: InputEvent) -> void:
	if not player.is_local or (HUD.instance and HUD.instance.is_blocking_input()):
		return
	if event.is_action_pressed("right_click"):
		_inspect()


func _inspect():
	if not inspecting:
		_rpc_inspect.rpc()
	else:
		_rpc_stop_inspect.rpc()

var case_top_tween: Tween

@rpc("any_peer", "call_local", "reliable")
func _rpc_inspect():
	_refresh_money_display()
	open_top()
	player.animator.play_action(inspect_animation, 0.2, 0.2)
	inspecting = true


## Updates the money label and bill stack to match the item's current amount.
func _refresh_money_display() -> void:
	var money_amount: int = get_current_money()
	if money_amount == _last_display_money:
		return
	_last_display_money = money_amount

	%MoneyLabel.text = str(money_amount) + "€"

	var cash_container = %CashContainer
	var fill_ratio: float = clampf(float(money_amount) / float(MAX_MONEY), 0.0, 1.0)
	var total_bills: int = cash_container.get_child_count()
	var visible_count: int = roundi(fill_ratio * total_bills)
	if money_amount > 0 and visible_count == 0:
		visible_count = 1

	for i in range(total_bills):
		cash_container.get_child(i).visible = (i < visible_count)


@rpc("any_peer", "call_local", "reliable")
func _rpc_stop_inspect():
	close_top()
	player.animator.play_action(idle_animation_override, 0.2, 0.2)
	inspecting = false


func close_top():
	var case_top = $HeldAnchor/briefcase/Top
	if case_top_tween:
		case_top_tween.kill()
	
	case_top_tween = create_tween()
	case_top_tween.tween_property(case_top, "rotation_degrees:x", 0.0, 0.25)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_IN_OUT)

func open_top():
	var case_top = $HeldAnchor/briefcase/Top
	if case_top_tween:
		case_top_tween.kill()
	
	case_top_tween = create_tween()
	case_top_tween.tween_property(case_top, "rotation_degrees:x", -90.0, 0.3)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_OUT)



func take_money(added_amount):
	var money_amount = ItemManager.get_item_data(item_id, "money", 0)
	ItemManager.set_and_sync_item_data(item_id, "money", money_amount + added_amount)
	print("Briefcase money: ", ItemManager.get_item_data(item_id, "money", -1))


func get_current_money() -> int:
	return ItemManager.get_item_data(item_id, "money", 0)


func get_max_to_add() -> int:
	return maxi(0, MAX_MONEY - get_current_money())





func _on_tree_exiting():
	print("Briefcase exiting tree")
	player.animator.cancel_action()
