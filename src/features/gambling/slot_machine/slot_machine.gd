extends Node3D

const ToggleButton = preload("res://src/features/interaction/buttons/toggle_button.gd")

const SYMBOL_COUNT: int = 7
const STEP_ANGLE: float = TAU / SYMBOL_COUNT

## Maximum amount a single spawned bill can hold; larger payouts are split into multiple bills.
const MAX_BILL_AMOUNT: int = PlayerInventory.CASH_STACK_LIMIT
## Delay between staggered bill spawns when a payout is split.
const BILL_SPAWN_DELAY: float = 0.4
## Force applied to bills at spawn
const BILL_LAUNCH_FORCE: Vector3 = Vector3(0, 0.0, 0.0)

## Multipliers mapped per symbol index for 2-of-a-kind combinations.
const COMBO_PAIRS: Dictionary[int, float] = {
	0: 0.0,
	1: 0.0,
	2: 0.5,
	3: 1.0,
	4: 1.0,
	5: 1.5,
	6: 2.5,
}

## Multipliers mapped per symbol index for 3-of-a-kind combinations.
const COMBO_TRIPLES: Dictionary[int, float] = {
	0: 3.0,
	1: 3.0,
	2: 4.0,
	3: 6.0,
	4: 10.0,
	5: 15.0,
	6: 60.0,
}

@export var sfx_win: AudioStream
@export var sfx_big_win: AudioStream
@export var sfx_jackpot: AudioStream
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
@onready var buttons: Array[ToggleButton] = [
	%ToggleButton1,
	%ToggleButton2,
	%ToggleButton3,
]
@onready var cash_interact: Interactable = %CashInteractable
@onready var balance_label: Label3D = %BalanceLabel3D

var _auto_animate_balance: bool = true
var balance: int = 0:
	set(val):
		var old: int = balance
		balance = val
		if is_inside_tree() and _auto_animate_balance:
			_animate_display_value(old, balance)

var is_spinning: bool = false
var roll_stage: int = 0
var current_bet: int = 0
var current_symbols: Array[int] = [0, 0, 0]

var _displayed_val: int = 0
var _display_prefix: String = ""
var _display_suffix: String = "€"
var _balance_tween: Tween
var _base_label_scale: Vector3

var _round_owner_player_id: int = 0 # 0 means not set


func _ready() -> void:
	_base_label_scale = balance_label.scale
	balance = 0
	$LevelInteract.interacted.connect(_lever_pulled)
	cash_interact.interacted.connect(_on_cash_input_interacted)
	_set_buttons_active(false)

	if Net.is_server:
		var initial_symbols: Array[int] = []
		for i in wheels.size():
			initial_symbols.append(randi() % SYMBOL_COUNT)
		_rpc_set_initial_symbols.rpc(initial_symbols)


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
		var bill: int = mini(MAX_BILL_AMOUNT, remaining)
		var id: int = ItemManager.create_item_of_type("cash", { "money": bill })
		ItemManager.create_world_item_for(id, %CashSpawnPos.global_position, %CashSpawnPos.global_rotation, Vector3.ZERO, _round_owner_player_id)
		remaining -= bill
		_rpc_on_cash_bill_spawned.rpc(remaining)
		if remaining > 0:
			await get_tree().create_timer(BILL_SPAWN_DELAY).timeout


@rpc("authority", "reliable", "call_local")
func _rpc_on_cash_bill_spawned(remaining: int) -> void:
	_play_sfx(sfx_cash_input)
	_animate_display_value(_displayed_val, remaining, 0.2)


func _update_label_text() -> void:
	balance_label.text = "%s%d%s" % [_display_prefix, _displayed_val, _display_suffix]


func _animate_display_value(from: int, to: int, duration: float = 0.35) -> void:
	if _balance_tween and _balance_tween.is_valid():
		_balance_tween.kill()

	_balance_tween = create_tween().set_parallel(true)

	_balance_tween.tween_method(
		func(v: int) -> void:
			_displayed_val = v
			_update_label_text(),
		from,
		to,
		duration,
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	var half_dur: float = duration * 0.5
	_balance_tween.tween_property(balance_label, "scale", _base_label_scale * 1.3, half_dur) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_balance_tween.tween_property(balance_label, "scale", _base_label_scale, half_dur) \
			.set_delay(half_dur).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _play_sfx(stream: AudioStream) -> void:
	if stream:
		Audio.play_sfx_3d(stream, global_position)


func _set_buttons_active(active: bool) -> void:
	for btn in buttons:
		btn.pressable = active


func _reset_buttons() -> void:
	for btn in buttons:
		btn.set_pressed_down(false)
		btn.pressable = false


func _lever_pulled(_player_id: int) -> void:
	if is_spinning:
		return
	if roll_stage == 0 and balance <= 0:
		return

	if Net.is_server:
		_start_spin_server()
	else:
		var holds: Array[bool] = [
			buttons[0].is_pressed_down(),
			buttons[1].is_pressed_down(),
			buttons[2].is_pressed_down(),
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

		_auto_animate_balance = false
		balance -= bet
		_auto_animate_balance = true

		_display_prefix = "[ "
		_display_suffix = "€ ]"

		_animate_display_value(current_bet, current_bet, 0.35)

	_set_buttons_active(false)
	$LevelInteract.prompt = ""
	$LevelInteract.active = false

	_play_sfx(sfx_lever)
	%LevelAnimationPlayer.play("pull_level")
	await %LevelAnimationPlayer.animation_finished

	var spun_any: bool = false
	var tweens: Array[Tween] = []

	for i: int in wheels.size():
		if roll_stage == 1 and holds[i]:
			continue

		spun_any = true
		var wheel: Node3D = wheels[i]
		var base_rotations: int = 4 + i * 2
		var current_lap: int = int(ceil(wheel.rotation.x / TAU))
		var target_x: float = (current_lap + base_rotations) * TAU - (target_symbols[i] * STEP_ANGLE)

		var apply_tease: bool = randf() < 0.4
		var tease_offset: float = (STEP_ANGLE * 0.35) * (1.0 if randf() < 0.5 else -1.0) if apply_tease else 0.0
		var roll_target_x: float = target_x + tease_offset

		var roll_duration: float = 2.8 + (i * 0.8)
		var snap_duration: float = 0.35

		var wheel_tween: Tween = create_tween()
		tweens.append(wheel_tween)

		wheel_tween.tween_property(wheel, "rotation:x", roll_target_x, roll_duration) \
				.set_trans(Tween.TRANS_QUAD) \
				.set_ease(Tween.EASE_OUT)

		if apply_tease:
			wheel_tween.tween_interval(0.08)
			wheel_tween.tween_property(wheel, "rotation:x", target_x, snap_duration) \
					.set_trans(Tween.TRANS_BACK) \
					.set_ease(Tween.EASE_OUT)

	if spun_any:
		_play_sfx(sfx_wheel_roll)
		_play_sfx(sfx_base_jingle)
		for tw in tweens:
			if tw.is_running():
				await tw.finished

	if roll_stage == 0:
		roll_stage = 1
		_set_buttons_active(true)
		$LevelInteract.prompt = "Spin 2"
		$LevelInteract.active = true
	else:
		roll_stage = 0
		_reset_buttons()

		var payout: int = _calculate_payout(current_symbols, current_bet)
		var multiplier: float =_get_multiplier(current_symbols)
		_display_prefix = ""
		_display_suffix = "€"

		if payout > 0:
			
			if multiplier > 30:
				_play_sfx(sfx_jackpot)
			elif multiplier > 2.5:
				_play_sfx(sfx_big_win)
			else:
				_play_sfx(sfx_win)
			
			
			_animate_display_value(current_bet, payout, 0.5)
			await get_tree().create_timer(0.6).timeout
			if Net.is_server:
				spawn_cash(payout)
		else:
			_play_sfx(sfx_lose)
			_animate_display_value(current_bet, balance, 0.3)

		current_bet = 0
		_round_owner_player_id = 0
		$LevelInteract.prompt = "Play"
		$LevelInteract.active = true

	is_spinning = false


func _calculate_payout(symbols: Array[int], bet: int) -> int:
	var counts: Dictionary = { }
	for sym in symbols:
		counts[sym] = counts.get(sym, 0) + 1

	for sym: int in counts:
		if counts[sym] == 3:
			return int(bet * COMBO_TRIPLES.get(sym, 0.0))
		if counts[sym] == 2:
			return int(bet * COMBO_PAIRS.get(sym, 0.0))

	return 0

func _get_multiplier(symbols: Array[int]) -> float:
	var counts: Dictionary = { }
	for sym in symbols:
		counts[sym] = counts.get(sym, 0) + 1
	
	for sym: int in counts:
		if counts[sym] == 3:
			return COMBO_TRIPLES.get(sym, 0.0)
		if counts[sym] == 2:
			return COMBO_PAIRS.get(sym, 0.0)
	
	return 0



func _on_cash_input_interacted(player_id: int) -> void:
	if is_spinning or roll_stage != 0:
		return
	var player := PlayerManager.get_player_node_by_id(player_id)
	var item := player.get_equipped_item()
	if not item or not item.item_type or not item.item_type.instance_data.has("money"):
		return
	var item_id: int = item.item_id
	var total_amount: int = ItemManager.get_item_data(item_id, "money", 0)

	if not HUD.instance:
		return
	var result := await HUD.instance.prompt_money(total_amount, total_amount)
	if result.cancelled or result.amount <= 0:
		return

	var equipped := player.get_equipped_item()
	if not equipped or equipped.item_id != item_id:
		return

	var put_in := mini(result.amount, total_amount)

	var remaining := total_amount - put_in
	if remaining <= 0:
		(player.inventory as PlayerInventory).pop_active_item()
		ItemManager.destroy_item(item_id)
	else:
		ItemManager.set_and_sync_item_data(item_id, "money", remaining)
	
	if _round_owner_player_id == 0:
		_rpc_set_round_owning_player.rpc(player_id)
	_rpc_add_balance.rpc(put_in)



@rpc("any_peer", "reliable", "call_local")
func _rpc_set_round_owning_player(player_id: int) -> void:
	_round_owner_player_id = player_id



@rpc("any_peer", "reliable", "call_local")
func _rpc_add_balance(money_added: int) -> void:
	balance += money_added
	_play_sfx(sfx_cash_input)


@rpc("authority", "reliable", "call_local")
func _rpc_set_initial_symbols(symbols: Array[int]) -> void:
	current_symbols = symbols
	for i in wheels.size():
		wheels[i].rotation.x = -symbols[i] * STEP_ANGLE
