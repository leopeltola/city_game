extends Node

## Emitted when any player's guilt amount changes.
signal guilt_changed(player_id: int, new_guilt: int)

## Emitted on the client when the local player's guilt amount changes.
signal local_guilt_changed(new_guilt: int)

## Emitted when any player's bounty amount changes.
signal bounty_changed(player_id: int, new_bounty: int)

## Emitted when a player is put under arrest (cuffed and escorted).
signal player_arrested(player_id: int)

## How long the escort may take before the server force-detains the suspect.
const ARREST_ESCORT_TIMEOUT_MS := 50000

## Guilt over committed crimes, which can be pictured.
## Schema: { player_id(int): Array[{"label": String, "time": int, "lasts": int, "amount": int}] }
var _guilt_data: Dictionary[int, Array] = {}

## Bounty (€) per player. If non-zero, player is wanted.
var _bounty_data: Dictionary[int, int] = {}

## player_id -> reserved JailCell while being escorted / detained. Server only.
var _jail_reservations: Dictionary[int, JailCell] = {}

## player_id -> deadline (msec) after which the escort is force-completed. Server only.
var _arrest_deadlines: Dictionary[int, int] = {}

## player_ids currently locked in a closed cell. Server-only bookkeeping (not a player
## state); police stop targeting them and it is cleared when they leave.
var _detained: Dictionary[int, bool] = {}


func _physics_process(_delta: float) -> void:
	if not Net.is_server:
		return

	var now: int = Time.get_ticks_msec()
	for player_id: int in _guilt_data.keys():
		var guilt_list: Array = _guilt_data[player_id]
		var expired: bool = false
		for i in range(guilt_list.size() - 1, -1, -1):
			var entry: Dictionary = guilt_list[i]
			if now - entry["time"] >= entry["lasts"]:
				guilt_list.remove_at(i)
				expired = true
		if expired:
			_sync_guilt_to_player(player_id)

	_process_arrests(now)


## Force-completes escorts that timed out.
func _process_arrests(now: int) -> void:
	for player_id: int in _arrest_deadlines.keys():
		if now >= _arrest_deadlines[player_id]:
			_arrest_deadlines.erase(player_id)
			_force_detain(player_id)


## Adds a guilt entry to a player with a duration in seconds.
func add_guilt(player_id: int, label: String, lasts_s: int, amount: int) -> void:
	if Net.is_server:
		_rpc_add_guilt(player_id, label, lasts_s, amount)
	elif Net.is_client:
		_rpc_add_guilt.rpc_id(1, player_id, label, lasts_s, amount)


## Converts a player's active guilt into bounty and clears their guilt.
func submit_guilt_to_bounty(player_id: int) -> void:
	if Net.is_server:
		_rpc_submit_guilt_to_bounty(player_id)
	elif Net.is_client:
		_rpc_submit_guilt_to_bounty.rpc_id(1, player_id)


## Sets the bounty for a specific player and synchronizes it across all peers.
func set_bounty(player_id: int, amount: int) -> void:
	if Net.is_server:
		_rpc_set_bounty(player_id, amount)
	elif Net.is_client:
		_rpc_set_bounty.rpc_id(1, player_id, amount)


## Adds [param amount] (€) straight onto a player's bounty, making them wanted at that
## moment. Unlike guilt, no photo is needed: used for crimes committed directly against
## the police.
func add_bounty(player_id: int, amount: int) -> void:
	if amount <= 0:
		return
	if Net.is_server:
		_rpc_add_bounty(player_id, amount)
	elif Net.is_client:
		_rpc_add_bounty.rpc_id(1, player_id, amount)


## Returns the total guilt of a given player in euros.
func get_guilt(player_id: int) -> int:
	if not _guilt_data.has(player_id):
		return 0
	var total: int = 0
	for entry: Dictionary in _guilt_data[player_id]:
		total += int(entry.get("amount", 0))
	return total


## Returns the local player's guilt on clients.
func get_local_guilt() -> int:
	if Net.is_server or _guilt_data.is_empty():
		return 0
	return get_guilt(_guilt_data.keys()[0])


## Returns whether the player currently has an active bounty.
func is_player_wanted(player_id: int) -> bool:
	return get_player_bounty(player_id) > 0


## Returns the wanted level (0 to 3) based on bounty tiers.
func get_wanted_level(player_id: int) -> int:
	var bounty: int = get_player_bounty(player_id)
	if bounty <= 0:
		return 0
	if bounty < 1000:
		return 1
	if bounty < 10000:
		return 2
	return 3


## Returns the current bounty for a given player.
func get_player_bounty(player_id: int) -> int:
	return _bounty_data.get(player_id, 0)


## Returns whether the player is currently locked in a closed cell.
func is_player_detained(player_id: int) -> bool:
	return _detained.has(player_id)


## Server-only bookkeeping: marks [param player_id] as locked in a cell. Clearing it
## frees their cell reservation. Not a player state.
func set_detained(player_id: int, value: bool) -> void:
	if not Net.is_server:
		return
	if value:
		_detained[player_id] = true
	else:
		_detained.erase(player_id)
		_jail_reservations.erase(player_id)
		_arrest_deadlines.erase(player_id)


## Puts a player under arrest: confiscates their belongings, opens their cell door and
## sends the target client to it. Returns true if a cell was available.
## Server-authoritative.
func arrest_player(player_id: int) -> bool:
	if Net.is_server:
		return _do_arrest(player_id)
	elif Net.is_client:
		_rpc_request_arrest.rpc_id(1, player_id)
	return false


## Called by the target client when the escorted player reaches their cell.
func notify_arrived_at_jail(player_id: int) -> void:
	if Net.is_server:
		_detain(player_id)
	elif Net.is_client:
		_rpc_notify_arrived.rpc_id(1, player_id)


## Server-side arrest sequence.
func _do_arrest(player_id: int) -> bool:
	assert(Net.is_server)
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if player == null:
		return false

	var cell := _reserve_jail_cell(player_id)
	if cell == null:
		return false

	_confiscate(player_id)
	assert(cell.door != null, "JailCell '%s' is missing its door export" % cell.name)
	cell.door.set_open(true)

	player._rpc_set_arrested.rpc(true, cell.get_stand_position())
	_arrest_deadlines[player_id] = Time.get_ticks_msec() + ARREST_ESCORT_TIMEOUT_MS
	player_arrested.emit(player_id)
	return true


## Closes the reserved cell on the suspect and takes the cuffs off (the closed door now
## does the containing). The cell area drains their bounty from here.
func _detain(player_id: int) -> void:
	assert(Net.is_server)
	if not _jail_reservations.has(player_id):
		return
	_arrest_deadlines.erase(player_id)

	var cell: JailCell = _jail_reservations.get(player_id)
	assert(cell != null, "No jail cell reserved for player %s" % player_id)
	cell.door.set_open(false)
	set_detained(player_id, true)

	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if player != null:
		player._rpc_set_arrested.rpc(false, Vector3.ZERO)


## Teleports a suspect that never reached their cell, then detains them.
func _force_detain(player_id: int) -> void:
	if not _jail_reservations.has(player_id):
		return
	var cell: JailCell = _jail_reservations.get(player_id)
	assert(cell != null, "No jail cell reserved for player %s" % player_id)
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if player != null:
		player._rpc_force_position.rpc(cell.get_stand_position())
	_detain(player_id)


## Picks a free JailCell (random tie-break) and reserves it for the player.
func _reserve_jail_cell(player_id: int) -> JailCell:
	if _jail_reservations.has(player_id):
		return _jail_reservations[player_id]

	var all_cells: Array[JailCell] = []
	var free_cells: Array[JailCell] = []
	var reserved: Array = _jail_reservations.values()
	for node: Node in get_tree().get_nodes_in_group("jail_cell"):
		var cell := node as JailCell
		if cell == null:
			continue
		all_cells.append(cell)
		if not reserved.has(cell):
			free_cells.append(cell)

	var pool: Array[JailCell] = free_cells if not free_cells.is_empty() else all_cells
	assert(not pool.is_empty(), "No JailCell nodes found in group 'jail_cell'")
	if pool.is_empty():
		return null
	var chosen: JailCell = pool[randi() % pool.size()]
	_jail_reservations[player_id] = chosen
	return chosen


## Confiscates the player's items and worn props, paying their value off the bounty.
func _confiscate(player_id: int) -> void:
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if player == null:
		return

	var total := _inventory_value(player.inventory) + _worn_value(player.prop_system)
	if total > 0:
		set_bounty(player_id, maxi(get_player_bounty(player_id) - total, 0))

	var pd: PlayerData = PlayerManager.get_player_by_id(player_id)
	if pd != null:
		player._rpc_confiscate.rpc_id(pd.peer_id)


## Total value of every item in [param inventory].
func _inventory_value(inventory: PlayerInventory) -> int:
	if inventory == null:
		return 0
	var total := 0
	for item_id: int in inventory.item_slots:
		if item_id != -1:
			total += _item_value(item_id)
	return total


## Total value of every prop worn on the actor.
func _worn_value(prop_system: PropSystem) -> int:
	if prop_system == null:
		return 0
	var total := 0
	for item_id: int in prop_system.worn_slots:
		if item_id != -1:
			total += _item_value(item_id)
	return total


## Value of a single item: cash stacks are worth their `money`, everything else its
## type's base_value.
func _item_value(item_id: int) -> int:
	var type_name: Variant = ItemManager.get_item_data(item_id, "type")
	if type_name == null:
		return 0
	if StringName(type_name) == &"cash":
		return int(ItemManager.get_item_data(item_id, "money", 0))
	var type: ItemType = ItemManager.get_item_type(type_name)
	return type.base_value if type != null else 0


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_arrest(player_id: int) -> void:
	assert(Net.is_server)
	_do_arrest(player_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_notify_arrived(player_id: int) -> void:
	assert(Net.is_server)
	_detain(player_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_add_guilt(player_id: int, label: String, lasts_s: int, amount: int) -> void:
	assert(Net.is_server)
	var entry: Dictionary = {
		"label": label,
		"time": Time.get_ticks_msec(),
		"lasts": lasts_s * 1000,
		"amount": amount,
	}
	if not _guilt_data.has(player_id):
		_guilt_data[player_id] = []
	_guilt_data[player_id].append(entry)
	_sync_guilt_to_player(player_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_submit_guilt_to_bounty(player_id: int) -> void:
	assert(Net.is_server)
	var guilt_sum: int = get_guilt(player_id)
	if guilt_sum <= 0:
		return

	_guilt_data[player_id] = []
	_sync_guilt_to_player(player_id)
	_set_server_bounty(player_id, get_player_bounty(player_id) + guilt_sum)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_bounty(player_id: int, amount: int) -> void:
	assert(Net.is_server)
	_set_server_bounty(player_id, amount)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_add_bounty(player_id: int, amount: int) -> void:
	assert(Net.is_server)
	_set_server_bounty(player_id, get_player_bounty(player_id) + amount)


func _set_server_bounty(player_id: int, amount: int) -> void:
	_bounty_data[player_id] = amount
	bounty_changed.emit(player_id, amount)
	_rpc_sync_bounty.rpc(player_id, amount)


func _sync_guilt_to_player(player_id: int) -> void:
	var total: int = get_guilt(player_id)
	guilt_changed.emit(player_id, total)

	var pd: PlayerData = PlayerManager.get_player_by_id(player_id)
	if pd:
		var entries: Array = _guilt_data.get(player_id, [])
		_rpc_sync_guilt.rpc_id(pd.peer_id, player_id, entries, total)


@rpc("authority", "call_remote", "reliable")
func _rpc_sync_guilt(player_id: int, entries: Array, total_guilt: int) -> void:
	assert(Net.is_client)
	_guilt_data[player_id] = entries
	guilt_changed.emit(player_id, total_guilt)
	local_guilt_changed.emit(total_guilt)


@rpc("authority", "call_remote", "reliable")
func _rpc_sync_bounty(player_id: int, amount: int) -> void:
	assert(Net.is_client)
	_bounty_data[player_id] = amount
	bounty_changed.emit(player_id, amount)
