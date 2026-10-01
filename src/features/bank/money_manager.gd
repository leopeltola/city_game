extends Node
## Server-authoritative bank accounts, transaction history and the unified payment API.
##
## Account balance and history are authoritative on the server. Balance is broadcast to
## every peer (a stolen debit card must be checked against its owner's balance), while
## history is synced to the owner only. Card ownership is not stored here: a debit card
## is an item, so its owner is read back from [ItemManager]'s replicated data.
##
## Money-moving calls are made on the acting client and route account mutations to the
## server through [method _rpc_request_balance_change]. Physical cash is mutated through
## [ItemManager], which already syncs item data. See AGENTS.md: cheating is not a concern.

## Emitted on every peer when a player's balance changes.
signal balance_changed(player_id: int, balance: int)

## Emitted on the owning client when a player's transaction history changes.
signal history_changed(player_id: int)

## Emitted on the acting client when the local player's card is issued or cancelled.
signal card_changed(player_id: int)

## Item type name of the debit card.
const CARD_TYPE := &"debit_card"

## Cost of issuing a debit card (€), charged to the account.
const CARD_PRICE := 500

## Maximum a single purchase may cost when paid with a debit card the payer does not own.
const STOLEN_CARD_PURCHASE_LIMIT := 1000

## History entries kept per player; oldest are dropped past this.
const MAX_HISTORY := 100

## Seconds to wait between spawned bills when a payout is split into multiple stacks.
const BILL_SPAWN_DELAY := 0.4

## player_id -> balance (€). Server-authoritative, broadcast on change.
var _balance: Dictionary[int, int] = { }

## player_id -> Array[{"amount": int, "label": String, "time": int}]. Server-authoritative,
## synced to the owner on change.
var _history: Dictionary[int, Array] = { }


func _ready() -> void:
	PlayerManager.player_left.connect(_on_player_left)
	PlayerManager.player_added.connect(_on_player_added)


func _on_player_left(pd: PlayerData) -> void:
	if Net.is_server:
		_balance.erase(pd.player_id)
		_history.erase(pd.player_id)


# Push known balances to a joining player so stolen-card checks work immediately.
func _on_player_added(pd: PlayerData) -> void:
	if not Net.is_server:
		return
	# Defer a frame so the joining client's scene is live before the syncs land.
	await get_tree().process_frame
	for player_id: int in _balance:
		_rpc_sync_balance.rpc_id(pd.peer_id, player_id, _balance[player_id])
	_rpc_sync_history.rpc_id(pd.peer_id, pd.player_id, _history_snapshot(pd.player_id))


#region Reads

## Returns [param player_id]'s account balance (€). Available on every peer.
func get_balance(player_id: int) -> int:
	return _balance.get(player_id, 0)


## Returns a copy of [param player_id]'s transaction history, oldest first.
func get_history(player_id: int) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	entries.assign(_history.get(player_id, []) as Array)
	return entries


## Asks the server to resend the local owner's history. Called by the finances UI so a
## client always has the current list, even if it missed earlier delta pushes.
func request_history() -> void:
	if Net.is_client:
		_rpc_request_history.rpc_id(Net.SERVER_ID)


## Returns every live debit card item owned by [param player_id], wherever it is.
func get_card_item_ids(player_id: int) -> Array[int]:
	var ids: Array[int] = []
	for item_id: int in ItemManager.get_item_ids_by_type(CARD_TYPE):
		if get_card_owner(item_id) == player_id:
			ids.append(item_id)
	return ids


## True while [param player_id] owns a debit card somewhere in the world.
func has_card(player_id: int) -> bool:
	return not get_card_item_ids(player_id).is_empty()


## Returns the player id the card belongs to, or 0 if unset.
func get_card_owner(item_id: int) -> int:
	return int(ItemManager.get_item_data(item_id, &"owner_player_id", 0))


## Returns the card's 4-digit number, or 0 if unset.
func get_card_number(item_id: int) -> int:
	return int(ItemManager.get_item_data(item_id, &"card_number", 0))


## Money held in [param player_id]'s equipped cash stack or briefcase, or 0 if none.
func get_held_money(player_id: int) -> int:
	var item := _get_equipped(player_id)
	if item == null or item.item_id == -1 or item.item_type == null:
		return 0
	if not item.item_type.instance_data.has("money"):
		return 0
	return int(ItemManager.get_item_data(item.item_id, "money", 0))


## Maximum [param player_id] can currently pay with their equipped medium. For a card
## owned by someone else this is capped at [constant STOLEN_CARD_PURCHASE_LIMIT].
func get_payable(player_id: int) -> int:
	var item := _get_equipped(player_id)
	if item == null or item.item_id == -1 or item.item_type == null:
		return 0
	if item.item_type.instance_data.has("money"):
		return int(ItemManager.get_item_data(item.item_id, "money", 0))
	if StringName(item.item_type.name) == CARD_TYPE:
		var owner_id := get_card_owner(item.item_id)
		var balance := get_balance(owner_id)
		if owner_id == player_id:
			return balance
		return mini(balance, STOLEN_CARD_PURCHASE_LIMIT)
	return 0


## True if [param player_id] can pay [param amount] with their equipped medium.
func can_pay(player_id: int, amount: int) -> bool:
	if amount <= 0:
		return false
	return get_payable(player_id) >= amount

#endregion

#region Transactions

## Pays [param amount] with the equipped medium: cash/briefcase money, or the card's
## account (owned or stolen). [param label] is recorded in the account's history.
## [br][br]
## Called on the acting client. Returns false when the medium cannot cover the amount.
func pay(player_id: int, amount: int, label: String = "Purchase") -> bool:
	if amount <= 0 or not can_pay(player_id, amount):
		return false
	var item := _get_equipped(player_id)
	if item == null or item.item_type == null:
		return false

	if StringName(item.item_type.name) == CARD_TYPE:
		var owner_id := get_card_owner(item.item_id)
		_request_balance_change(owner_id, -amount, label)
		if owner_id != player_id:
			MessageManager.send_message_to(
				owner_id,
				"Bank",
				"Debit card used",
				"%d€ was spent on your debit card (%s)." % [amount, label],
			)
		return true

	return _take_from_money_item(player_id, amount)


## Deducts [param amount] from the equipped cash/briefcase only (never a card). Used by
## cash-only machines such as the slot machine.
## [br][br]
## Called on the acting client.
func take_cash(player_id: int, amount: int) -> bool:
	if amount <= 0:
		return false
	var item := _get_equipped(player_id)
	if item == null or item.item_type == null or not item.item_type.instance_data.has("money"):
		return false
	if get_held_money(player_id) < amount:
		return false
	return _take_from_money_item(player_id, amount)


## Moves [param amount] from the equipped cash/briefcase into [param player_id]'s account
## and notifies them by mail.
## [br][br]
## Called on the acting client. Returns false when no money is held or it is short.
func deposit(player_id: int, amount: int) -> bool:
	if amount <= 0:
		return false
	var held := get_held_money(player_id)
	if held <= 0 or amount > held:
		return false
	if not _take_from_money_item(player_id, amount):
		return false

	_request_balance_change(player_id, amount, "Deposit")
	var projected := get_balance(player_id) + amount
	MessageManager.send_message_to(
		player_id,
		"Bank",
		"Deposit received",
		"%d€ was deposited into your account. Balance: %d€." % [amount, projected],
	)
	return true


## Issues a debit card to [param player_id], charging [constant CARD_PRICE] to their
## account. Requires no existing card and enough balance. Tries the owner's inventory
## first and drops the card at [param spawn_pos] when it is full.
## [br][br]
## Called on the acting client. Returns false when the purchase is not allowed.
func issue_card(player_id: int, spawn_pos: Vector3, spawn_rot: Vector3 = Vector3.ZERO) -> bool:
	if has_card(player_id) or get_balance(player_id) < CARD_PRICE:
		return false

	_request_balance_change(player_id, -CARD_PRICE, "Debit card issued")

	var item_id := ItemManager.create_item_of_type(
		CARD_TYPE,
		{ &"owner_player_id": player_id, &"card_number": randi_range(1000, 9999) },
	)
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if player == null or player.inventory == null or not player.inventory.try_add_item(item_id):
		ItemManager.create_world_item_for(item_id, spawn_pos, spawn_rot)

	MessageManager.send_message_to(
		player_id,
		"Bank",
		"Debit card issued",
		"A new debit card was issued for %d€ and sent to you." % CARD_PRICE,
	)
	card_changed.emit(player_id)
	return true


## Destroys every debit card owned by [param player_id], wherever it currently is, and
## notifies them by mail.
## [br][br]
## Called on the acting client.
func cancel_card(player_id: int) -> void:
	var ids := get_card_item_ids(player_id)
	if ids.is_empty():
		return
	for item_id: int in ids:
		ItemManager.destroy_item(item_id)
	MessageManager.send_message_to(
		player_id,
		"Bank",
		"Debit card cancelled",
		"Your debit card was cancelled. Keep the money."
	)
	card_changed.emit(player_id)


## Credits [param amount] to [param player_id]'s account and records [param label] in its
## history. Called on the acting peer; routes the mutation to the server. Used for rewards
## and payouts.
func credit_account(player_id: int, amount: int, label: String = "Reward") -> void:
	if amount <= 0:
		return
	_request_balance_change(player_id, amount, label)


## Server-side: spawns [param amount] (€) as cash world items at [param position],
## splitting into stacks no larger than [constant PlayerInventory.CASH_STACK_LIMIT] and
## staggering the spawns by [constant BILL_SPAWN_DELAY]. [param owner_player_id] marks the
## bills as owned (stealing them counts as theft). [param on_bill] is called with the
## remaining amount after each bill, for caller-side presentation.
func spawn_cash_stacks(
	amount: int,
	position: Vector3,
	rotation: Vector3 = Vector3.ZERO,
	owner_player_id: int = 0,
	on_bill: Callable = Callable(),
) -> void:
	assert(Net.is_server, "spawn_cash_stacks is server-only")
	var remaining := amount
	while remaining > 0:
		var bill: int = mini(PlayerInventory.CASH_STACK_LIMIT, remaining)
		var item_id: int = ItemManager.create_item_of_type(&"cash", { &"money": bill })
		ItemManager.create_world_item_for(item_id, position, rotation, Vector3.ZERO, owner_player_id)
		remaining -= bill
		if on_bill.is_valid():
			on_bill.call(remaining)
		if remaining > 0:
			await get_tree().create_timer(BILL_SPAWN_DELAY).timeout

#endregion

#region Internal

# Returns the ItemEquip currently mounted for [param player_id], or null.
func _get_equipped(player_id: int) -> ItemEquip:
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if player == null:
		return null
	return player.get_equipped_item()


# Deducts [param amount] from the actor's equipped money container. Empties a cash stack
# by consuming it; leaves an emptied briefcase equipped.
func _take_from_money_item(player_id: int, amount: int) -> bool:
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if player == null or player.inventory == null:
		return false
	var item := player.get_equipped_item()
	if item == null or item.item_id == -1 or item.item_type == null:
		return false
	if not item.item_type.instance_data.has("money"):
		return false

	var item_id := item.item_id
	var total := int(ItemManager.get_item_data(item_id, "money", 0))
	if amount <= 0 or amount > total:
		return false

	var remaining := total - amount
	if remaining <= 0 and item.item_type.name == &"cash":
		player.inventory.pop_active_item()
		ItemManager.destroy_item(item_id)
	else:
		ItemManager.set_and_sync_item_data(item_id, "money", remaining)
	return true


func _request_balance_change(player_id: int, delta: int, label: String) -> void:
	if Net.is_server:
		_apply_balance_change(player_id, delta, label)
	elif Net.is_client:
		_rpc_request_balance_change.rpc_id(Net.SERVER_ID, player_id, delta, label)


func _apply_balance_change(player_id: int, delta: int, label: String) -> void:
	assert(Net.is_server, "_apply_balance_change is server-only")
	var new_balance := maxi(get_balance(player_id) + delta, 0)
	_balance[player_id] = new_balance
	_add_history(player_id, delta, label)
	_rpc_sync_balance.rpc(player_id, new_balance)
	_sync_history_to_owner(player_id)


func _add_history(player_id: int, amount: int, label: String) -> void:
	if not _history.has(player_id):
		_history[player_id] = []
	_history[player_id].append({
		"amount": amount,
		"label": label,
		"time": int(Time.get_unix_time_from_system()),
	})
	while _history[player_id].size() > MAX_HISTORY:
		_history[player_id].pop_front()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_balance_change(player_id: int, delta: int, label: String) -> void:
	assert(Net.is_server)
	_apply_balance_change(player_id, delta, label)


@rpc("authority", "call_remote", "reliable")
func _rpc_sync_balance(player_id: int, amount: int) -> void:
	assert(Net.is_client)
	_balance[player_id] = amount
	balance_changed.emit(player_id, amount)


func _sync_history_to_owner(player_id: int) -> void:
	# The authoritative peer is a player too, and the sync RPCs are `call_remote`, so it
	# must refresh its own UI directly.
	history_changed.emit(player_id)
	var pd: PlayerData = PlayerManager.get_player_by_id(player_id)
	if pd == null:
		push_error("MoneyManager: no PlayerData for player %d; history sync skipped." % player_id)
	elif pd.peer_id != multiplayer.get_unique_id():
		# `call_remote` RPCs to the local peer are rejected; the emit above already
		# refreshed the authoritative UI.
		_rpc_sync_history.rpc_id(pd.peer_id, player_id, _history_snapshot(player_id))


# Returns [param player_id]'s history as a plain (untyped) Array, the shape the RPC
# argument is declared with.
func _history_snapshot(player_id: int) -> Array:
	var entries: Array = []
	entries.assign(get_history(player_id))
	return entries


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_history() -> void:
	assert(Net.is_server)
	var pd: PlayerData = PlayerManager.get_player_by_peer_id(multiplayer.get_remote_sender_id())
	if pd:
		_sync_history_to_owner(pd.player_id)


@rpc("authority", "call_remote", "reliable")
func _rpc_sync_history(player_id: int, entries: Array) -> void:
	assert(Net.is_client)
	var copy: Array[Dictionary] = []
	copy.assign(entries)
	_history[player_id] = copy
	history_changed.emit(player_id)

#endregion
