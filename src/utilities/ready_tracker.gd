class_name ReadyTrackerSingleton
extends Node
## Global Autoload utility
## Tracks peer readiness for specific events on the server.
##
## @tutorial (Usage Example):
## [codeblock]
## # Inside a gameplay script (e.g., LevelManager.gd)
## func _ready() -> void:
##     if Net.is_server:
##         ReadyTracker.everyone_ready.connect(_on_all_peers_ready)
##     
##     # Both clients and server declare they are ready
##     ReadyTracker.set_ready("level_loaded")
##
## func _on_all_peers_ready(event: String) -> void:
##     if event == "level_loaded":
##         # Server starts the match or RPCs clients to start
##         rpc_start_match.rpc()
##
## @rpc("authority", "call_local", "reliable")
## func rpc_start_match() -> void:
##     # Executes on both Net.is_server and Net.is_client
##     begin_gameplay_loop()
## [/codeblock]

## Emitted on server when everyone has readied event.
signal everyone_ready(event: String)

# Stores data as { "event_name": { peer_id: true } }
var _data: Dictionary = { }


func _ready() -> void:
	if multiplayer.has_multiplayer_peer():
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)


## Registers the local peer (client or server) as ready for a specific event.
func set_ready(event: String) -> void:
	rpc_update_ready.rpc(event)


## Returns true on the server when all currently-connected peers (including the server)
## have readied [event]. Recomputes against the live peer list, so it also recovers
## if a peer disconnects before readying.
func is_event_complete(event: String) -> bool:
	if not multiplayer.is_server():
		return false
	if not _data.has(event):
		return false
	return _data[event].size() >= multiplayer.get_peers().size() + 1


## Resets the tracking state for a specific event. Server-only.
func reset(event: String) -> void:
	assert(multiplayer.is_server(), "reset must be called on the server.")
	_data.erase(event)


@rpc("any_peer", "call_local", "reliable")
func rpc_update_ready(event: String) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()

	if not _data.has(event):
		_data[event] = { }

	_data[event][peer_id] = true
	_check_completion(event)


func _check_completion(event: String) -> void:
	if not _data.has(event):
		return

	var ready_peers: Dictionary = _data[event]
	var total_required := multiplayer.get_peers().size() + 1 # All clients + server

	if ready_peers.size() >= total_required:
		everyone_ready.emit(event)


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	# Remove disconnected peer from all active event pools
	for event in _data.keys():
		if _data[event].erase(peer_id):
			# Re-evaluate completion status since the required threshold dropped
			_check_completion(event)
