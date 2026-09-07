extends Interactable

@export var cash_spawn_pos: Node3D = null


func _ready() -> void:
	assert(cash_spawn_pos)


func interact(player_id: int) -> void:
	if not HUD.instance:
		return

	var result := await HUD.instance.prompt_welfare()
	if result.cancelled:
		return

	var pd := PlayerManager.get_player_by_id(player_id)

	if pd.player_name != result.player_name:
		# Player name doesn't match
		return
	if result.chosen_benefits.size() == 0:
		# No benefits chosen
		return
	if result.chosen_benefits.size() >= 2:
		# Chose more than 1 benefit (not allowed)
		return
	if not result.terms_accepted:
		# Terms not accepted
		return
	
	spawn_cash(20)


## Spawns cash into the world via the server. Payouts above the bill cap are split into
## multiple bills, staggered by [BILL_SPAWN_DELAY].
func spawn_cash(amount: int) -> void:
	if Net.is_client:
		_rpc_spawn_cash.rpc_id(1, amount)
	elif Net.is_server:
		_rpc_spawn_cash(amount)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_spawn_cash(amount: int) -> void:
	assert(Net.is_server)
	var remaining: int = amount
	while remaining > 0:
		var bill: int = mini(1000, remaining)
		var id: int = ItemManager.create_item_of_type("cash", { "amount": bill })
		ItemManager.create_world_item_for(id, cash_spawn_pos.global_position, cash_spawn_pos.global_rotation)
		remaining -= bill
		if remaining > 0:
			await get_tree().create_timer(.4).timeout
