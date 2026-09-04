extends Node3D

const SYMBOL_COUNT: int = 7
const STEP_ANGLE: float = TAU / SYMBOL_COUNT

## Maximum amount a single spawned bill can hold; larger payouts are split into multiple bills.
const MAX_BILL_AMOUNT: int = PlayerInventory.CASH_STACK_LIMIT
## Delay between staggered bill spawns when a payout is split.
const BILL_SPAWN_DELAY: float = 0.5

@export var sfx_win: AudioStream
@export var sfx_lose: AudioStream
@export var sfx_cash_input: AudioStream
@export var sfx_wheel_roll: AudioStream
@export var sfx_lever: AudioStream
@export var sfx_base_jingle: AudioStream

@onready var wheels: Array[Node3D] = [
	$slot_machine/Wheel1,
	$slot_machine/Wheel2,
	$slot_machine/Wheel3,
]
@onready var buttons: Array[InteractableButton] = [
	%InteractableButton1,
	%InteractableButton2,
	%InteractableButton3,
]
@onready var cash_interact: Interactable = %CashInteractable
@onready var balance_label: Label3D = %BalanceLabel3D

var balance := 0:
	set(val):
		balance = val
		if is_inside_tree():
			balance_label.text = "%s€" % balance

var is_spinning: bool = false
var roll_stage: int = 0
var current_bet: int = 0
var current_symbols: Array[int] = [0, 0, 0]


func _ready() -> void:
	balance = 0
	$LevelInteract.interacted.connect(_lever_pulled)
	cash_interact.interacted.connect(_on_cash_input_interacted)
	_set_buttons_active(false)


## Spawns cash into the world via the server. Payouts above the bill cap are split into
## multiple bills, staggered by [BILL_SPAWN_DELAY]. Plays the cash register sound per bill.
func spawn_cash(amount: int) -> void:
	if Net.is_client:
		_rpc_spawn_cash.rpc_id(1, amount)
	elif Net.is_server:
		_rpc_spawn_cash(amount)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_spawn_cash(amount: int) -> void:
	assert(Net.is_server)
	var remaining := amount
	while remaining > 0:
		var bill := mini(MAX_BILL_AMOUNT, remaining)
		var id: int = ItemManager.create_item_of_type("cash", { "amount": bill })
		ItemManager.create_world_item_for(id, %CashSpawnPos.global_position, %CashSpawnPos.global_rotation)
		_rpc_play_cash_spawn_sfx.rpc()
		remaining -= bill
		if remaining > 0:
			await get_tree().create_timer(BILL_SPAWN_DELAY).timeout


@rpc("authority", "reliable", "call_local")
func _rpc_play_cash_spawn_sfx() -> void:
	_play_sfx(sfx_cash_input)


func _play_sfx(stream: AudioStream) -> void:
	if stream:
		Audio.play_sfx_3d(stream, global_position)


func _set_buttons_active(active: bool) -> void:
	for btn in buttons:
		btn.toggleable = active


func _reset_buttons() -> void:
	for btn in buttons:
		btn.toggle_down = false
		btn.toggleable = false


func _lever_pulled(_player_id: int) -> void:
	if is_spinning:
		return
	if roll_stage == 0 and balance <= 0:
		return

	if Net.is_server:
		_start_spin_server()
	else:
		var holds: Array[bool] = [
			buttons[0].toggle_down,
			buttons[1].toggle_down,
			buttons[2].toggle_down,
		]
		_rpc_request_spin.rpc_id(1, holds)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_request_spin(holds: Array[bool]) -> void:
	assert(Net.is_server)
	if is_spinning:
		return
	if roll_stage == 0 and balance <= 0:
		return
	_start_spin_server(holds)


func _start_spin_server(holds: Array[bool] = [false, false, false]) -> void:
	var next_symbols: Array[int] = current_symbols.duplicate()
	for i in wheels.size():
		if roll_stage == 0 or not holds[i]:
			next_symbols[i] = randi() % SYMBOL_COUNT

	var bet: int = current_bet
	if roll_stage == 0:
		bet = balance

	_rpc_execute_spin.rpc(next_symbols, holds, bet, roll_stage)


@rpc("authority", "reliable", "call_local")
func _rpc_execute_spin(target_symbols: Array[int], holds: Array[bool], bet: int, stage: int) -> void:
	is_spinning = true
	roll_stage = stage
	current_symbols = target_symbols

	if roll_stage == 0:
		current_bet = bet
		balance -= bet

	_set_buttons_active(false)
	$LevelInteract.prompt = ""
	$LevelInteract.active = false

	_play_sfx(sfx_lever)
	%LevelAnimationPlayer.play("pull_level")
	await %LevelAnimationPlayer.animation_finished

	var tween: Tween = create_tween().set_parallel(true)
	var spun_any: bool = false

	for i: int in wheels.size():
		if roll_stage == 1 and holds[i]:
			continue

		spun_any = true
		var wheel: Node3D = wheels[i]
		var base_rotations: int = 4 + i * 2
		var current_lap: int = int(ceil(wheel.rotation.x / TAU))
		var target_x: float = (current_lap + base_rotations) * TAU + (target_symbols[i] * STEP_ANGLE)
		var duration: float = 2.0 + (i * 0.7)

		tween.tween_property(wheel, "rotation:x", target_x, duration)\
			.set_trans(Tween.TRANS_CUBIC)\
			.set_ease(Tween.EASE_OUT)

	if spun_any:
		_play_sfx(sfx_wheel_roll)
		await tween.finished

	if roll_stage == 0:
		roll_stage = 1
		_set_buttons_active(true)
		$LevelInteract.prompt = "Spin 2"
		$LevelInteract.active = true
	else:
		roll_stage = 0
		_reset_buttons()

		var payout: int = _calculate_payout(current_symbols, current_bet)
		if payout > 0:
			_play_sfx(sfx_win)
			if Net.is_server:
				spawn_cash(payout)
		else:
			_play_sfx(sfx_lose)

		current_bet = 0
		$LevelInteract.prompt = "Play"
		$LevelInteract.active = true

	is_spinning = false


func _calculate_payout(symbols: Array[int], bet: int) -> int:
	if symbols[0] == symbols[1] and symbols[1] == symbols[2]:
		return bet * 3.0
	if symbols[0] == symbols[1] or symbols[1] == symbols[2] or symbols[0] == symbols[2]:
		return int(bet * 1.5)
	return 0


func _on_cash_input_interacted(player_id: int) -> void:
	if is_spinning or roll_stage != 0:
		return
	var player := PlayerManager.get_player_node_by_id(player_id)
	var item := player.get_equipped_item()
	if not item or item.item_type.name != "cash":
		return
	var item_id: int = item.item_id
	var total_amount: int = ItemManager.get_item_data(item_id, "amount", 0)

	if not HUD.instance:
		return
	var result := await HUD.instance.prompt_money(total_amount)
	if result.cancelled or result.amount <= 0:
		return

	var equipped := player.get_equipped_item()
	if not equipped or equipped.item_id != item_id:
		return

	var put_in := mini(result.amount, total_amount)

	var remaining := total_amount - put_in
	if remaining <= 0:
		player.inventory.pop_active_item()
		ItemManager.destroy_item(item_id)
	else:
		ItemManager.set_and_sync_item_data(item_id, "amount", remaining)

	_rpc_add_balance.rpc(put_in)


@rpc("any_peer", "reliable", "call_local")
func _rpc_add_balance(money_added: int) -> void:
	balance += money_added
	_play_sfx(sfx_cash_input)
