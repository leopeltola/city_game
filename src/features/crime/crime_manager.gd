extends Node

## Emitted when any player's guilt amount changes.
signal guilt_changed(player_id: int, new_guilt: int)

## Emitted on the client when the local player's guilt amount changes.
signal local_guilt_changed(new_guilt: int)

## Emitted when any player's bounty amount changes.
signal bounty_changed(player_id: int, new_bounty: int)

## Guilt over committed crimes, which can be pictured.
## Schema: { player_id(int): Array[{"label": String, "time": int, "lasts": int, "amount": int}] }
var _guilt_data: Dictionary[int, Array] = {}

## Bounty (€) per player. If non-zero, player is wanted.
var _bounty_data: Dictionary[int, int] = {}


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
