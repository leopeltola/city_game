extends Interactable

const WELFARE_CD_MS := 60_000

@export var cash_spawn_pos: Node3D = null
@export var cash_spawn_sfx: AudioStream = null

var _sw: Stopwatch = Stopwatch.new()


func _ready() -> void:
	assert(cash_spawn_pos)
	_sw.start_time_ms = _sw.start_time_ms - WELFARE_CD_MS


func interact(player_id: int) -> void:
	if not HUD.instance:
		return

	var result := await HUD.instance.prompt_welfare()
	if result.cancelled:
		return

	await get_tree().create_timer(.7).timeout

	var pd := PlayerManager.get_player_by_id(player_id)

	if _sw.measure() < WELFARE_CD_MS:
		# Has gotten welfare within last minute
		MessageManager.send_message_to(PlayerManager.get_local_player().player_id, "Kela", "Welfare Application Rejected", "Try again in %s seconds. " % roundi((WELFARE_CD_MS - _sw.measure()) / 1000.0))
		return
	if pd.player_name != result.player_name:
		# Player name doesn't match
		MessageManager.send_message_to(PlayerManager.get_local_player().player_id, "Kela", "Welfare Application Rejected", "Name incorrect.")
		return
	if result.chosen_benefits.size() == 0:
		# No benefits chosen
		MessageManager.send_message_to(PlayerManager.get_local_player().player_id, "Kela", "Welfare Application Rejected", "No benefits were applied for.")
		return
	if result.chosen_benefits.size() >= 2:
		# Chose more than 1 benefit (not allowed)
		MessageManager.send_message_to(PlayerManager.get_local_player().player_id, "Kela", "Welfare Application Rejected", "Too many benefits selected. For multiple benefits, file separate applications.")
		return
	if not result.terms_accepted:
		# Terms not accepted
		MessageManager.send_message_to(PlayerManager.get_local_player().player_id, "Kela", "Welfare Application Rejected", "Terms not accepted")
		return

	MessageManager.send_message_to(PlayerManager.get_local_player().player_id, "Kela", "Welfare Application Accepted", "Your welfare application has been accepted. \n20€ has been given to you as cash.")
	spawn_cash(20)
	_sw.restart()


## Spawns cash into the world via the server. Payouts above the bill cap are split into
## multiple bills, staggered by [BILL_SPAWN_DELAY].
func spawn_cash(amount: int) -> void:
	if Net.is_client:
		Audio.play_sfx_3d(cash_spawn_sfx, cash_spawn_pos.global_position, 0, 30)
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
