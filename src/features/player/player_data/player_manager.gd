extends Node
## Manages lifecycle and lookup for [PlayerData] instances across the network.

signal player_added(player_data: PlayerData)
signal player_left(player_data: PlayerData)

const PlayerDataScene := preload("res://src/features/player/player_data/player_data.tscn")

## Peer ID: [PlayerData] mapping.
var _player_data: Dictionary[int, PlayerData] = { }
## Player ID: [PlayerData] mapping.
var _player_nodes: Dictionary[int, Player] = { }


func _ready() -> void:
	Net.peer_connected.connect(_on_net_peer_connected)
	Net.peer_disconnected.connect(_on_net_peer_disconnected)
	Net.connection_closed.connect(_reset)

	%PlayerSpawner.spawn_function = _spawn_custom_player
	%PlayerSpawner.spawned.connect(_on_node_spawned)
	%PlayerSpawner.despawned.connect(_on_node_despawned)

#region Network Handlers

func _on_net_peer_connected(id: int) -> void:
	if Net.is_server:
		_create_player_for(id)


func _on_net_peer_disconnected(id: int) -> void:
	if Net.is_server:
		# Only server removes the node manually
		# PlayerSpawner syncs this to clients
		var p := get_player_by_peer_id(id)
		if p:
			_remove_player(p)


func _on_node_spawned(node: Node) -> void:
	var player := node as PlayerData
	assert(player)
	if not player:
		return

	# Register the node in the local dictionary
	_player_data[player.peer_id] = player

	player_added.emit(player)
	print("PlayerData spawned on %s\n\t%s" % [multiplayer.get_unique_id(), player])

	push_warning("%s joined" % player.player_name)
	ToastOverlay.show_info("%s joined" % player.player_name)


func _on_node_despawned(node: Node) -> void:
	_remove_player(node as PlayerData)


## Callback for [MultiplayerSpawner] to initialize [PlayerData] with network identity.
func _spawn_custom_player(data: Variant) -> Node:
	var p := PlayerDataScene.instantiate()

	# Extract data from the variant passed during spawn()
	p.player_id = data.get("player_id")
	p.peer_id = data.get("peer_id")
	p.player_name = data.get("player_name")

	# Set the node name so it is consistent across the network
	p.name = "%s_%s" % [p.player_id, p.peer_id]

	return p

#endregion

#region Logic

## Returns the [PlayerData] associated with a unique internal player ID.
func get_player_by_id(player_id: int) -> PlayerData:
	for p in _player_data.values():
		if is_instance_valid(p) and p.player_id == player_id:
			return p
	return null


## Returns the [PlayerData] for this local machine. Throws an assertion error if not found.
func get_local_player() -> PlayerData:
	var lp = get_local_player_or_null()
	assert(lp != null, "Could not find local player.")
	return lp


## Returns the [PlayerData] for this local machine, or [code]null[/code] if unassigned.
func get_local_player_or_null() -> PlayerData:
	return get_player_by_peer_id(multiplayer.get_unique_id())


## Returns the [PlayerData] associated with a specific network peer ID.
func get_player_by_peer_id(peer_id: int) -> PlayerData:
	return _player_data.get(peer_id)


## Returns the total number of connected players.
func get_player_count() -> int:
	return _player_data.size()


## Returns a list of all active [PlayerData] nodes.
func get_players() -> Array[PlayerData]:
	return _player_data.values()


func get_player_nodes() -> Array[Player]:
	return _player_nodes.values()


func get_player_node_by_id(player_id: int) -> Player:
	for p in _player_nodes.values():
		if is_instance_valid(p) and p.player_id == player_id:
			return p
	return null


func get_local_player_node_or_null() -> Player:
	var lp = get_local_player_or_null()
	if lp:
		return get_player_node_by_id(lp.player_id)
	return null


func register_player_node(player: Player) -> void:
	assert(player)
	_player_nodes[player.player_id] = player


## Creates and spawns a player node for the specified peer. Must be called on server.
func _create_player_for(peer_id: int) -> PlayerData:
	assert(Net.is_server)

	var player_id = _player_data.size() + 1
	var data = {
		"player_id": player_id,
		"peer_id": peer_id,
		"player_name": "Player %s" % player_id,
	}

	# spawn() triggers the custom function on the server and notifies clients
	var pd = %PlayerSpawner.spawn(data) as PlayerData

	# Keep the server dictionary authoritative. _on_node_spawned also registers via
	# the spawned signal, but registering here guarantees lookups work regardless.
	_player_data[pd.peer_id] = pd
	player_added.emit(pd)

	push_warning("%s joined" % pd.player_name)
	ToastOverlay.show_info("%s joined" % pd.player_name)

	return pd


func _reset() -> void:
	var ps := _player_data.values().duplicate()
	for p in ps:
		if is_instance_valid(p):
			p.queue_free()
	_player_data.clear()


func _remove_player(pd: PlayerData) -> void:
	_player_data.erase(pd.peer_id)
	player_left.emit(pd)
	push_warning("%s left" % pd.player_name)
	ToastOverlay.show_info("%s left" % pd.player_name)

#endregion
