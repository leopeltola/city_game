class_name Lobby
extends Node

## Lobby orchestration for the main scene. Deliberately a local node under [Main], not
## an autoload: it is only meaningful before gameplay. RPC paths stay consistent across
## peers because every instance (including the headless server) loads main.tscn and so
## always has /root/Main/Lobby.
##
## Roles:
## - Server: the authoritative process. In production it is a headless child spawned by
##   the creating client.
## - Host (leader): the player allowed to start the match. In production it is the client
##   that created the lobby, proven by a one-time token.
##
## Dev networking (`--dev-server` / `--dev-join`) bypasses all of this: the lobby stays
## inert and [Main] auto-starts the match directly.

signal lobby_joined
signal leader_changed(leader_peer_id: int)
signal lobby_failed(reason: String)
signal starting_game

const DEFAULT_CAPACITY := 16
const LEADER_SYNC_INTERVAL := 0.5
const MAX_LEADER_SYNC_ATTEMPTS := 60
## Bounded retries for joining the room once it has been seen on the lobby feed.
const MAX_JOIN_RETRIES := 10
const JOIN_RETRY_DELAY := 0.5
## A freshly spawned server that never gets a leader shuts itself down after this long.
const SERVER_IDLE_TIMEOUT := 180.0
## How long to wait for a freshly spawned server to publish its lobby feed entry.
const ROOM_WAIT_TIMEOUT := 20.0

static var instance: Lobby = null

var _is_dedicated_server := false
var _dev_mode := false
var _creating := false
var _waiting_for_room := false
var _leaving := false
var _game_started := false
var _room_id := ""
var _leader_peer := 0
var _expected_leader_token := ""
var _pending_leader_token := ""
var _leader_sync_attempts := 0
var _join_retries := 0
var _server_process := ServerProcess.new()
var _leader_sync_timer: Timer
var _idle_timer: Timer
var _room_wait_timer: Timer


func _ready() -> void:
	instance = self

	_leader_sync_timer = Timer.new()
	_leader_sync_timer.wait_time = LEADER_SYNC_INTERVAL
	_leader_sync_timer.timeout.connect(_sync_leader)
	add_child(_leader_sync_timer)

	_idle_timer = Timer.new()
	_idle_timer.one_shot = true
	_idle_timer.wait_time = SERVER_IDLE_TIMEOUT
	_idle_timer.timeout.connect(_on_idle_timeout)
	add_child(_idle_timer)

	_room_wait_timer = Timer.new()
	_room_wait_timer.one_shot = true
	_room_wait_timer.wait_time = ROOM_WAIT_TIMEOUT
	_room_wait_timer.timeout.connect(_on_room_wait_timeout)
	add_child(_room_wait_timer)

	# Dev networking drives itself (ENET plus the auto-start in Main). The lobby,
	# leader and lobby screen are production-only, so stay completely uninvolved here.
	_dev_mode = "--dev-server" in OS.get_cmdline_args() or "--dev-join" in OS.get_cmdline_args()
	if _dev_mode:
		return

	Net.peer_connected.connect(_on_peer_connected)
	Net.peer_disconnected.connect(_on_peer_disconnected)
	Net.connection_closed.connect(_on_connection_closed)
	Net.joined_game.connect(_on_joined_game)
	Net.join_failed.connect(_on_join_failed)


#region Public API

## Spawns a headless server and joins it as the lobby's host. The client connects as a
## regular client and proves its leadership with a one-time token. Returns an Error.
func create_lobby(room_id: String) -> Error:
	if _dev_mode:
		return ERR_UNAVAILABLE
	if Net.is_connected:
		return ERR_ALREADY_IN_USE

	_creating = true
	_room_id = room_id
	_pending_leader_token = _generate_token()

	var spawn_error := _server_process.spawn(room_id, _pending_leader_token, DEFAULT_CAPACITY)
	if spawn_error != OK:
		_reset()
		return spawn_error

	_start_waiting_for_room()
	return OK


## Joins an existing lobby (browsed from the lobby list). This client is not the host.
func join_lobby(room_id: String) -> Error:
	if _dev_mode:
		return ERR_UNAVAILABLE
	if Net.is_connected:
		return ERR_ALREADY_IN_USE

	_creating = false
	_pending_leader_token = ""
	_room_id = room_id
	return Net.start_joining_game(room_id)


## Boots this instance as the authoritative server for [param room_id]. Called from
## [Main] when the process was launched with `--server`.
func start_dedicated_server(room_id: String, leader_token: String, capacity: int) -> void:
	_is_dedicated_server = true
	_room_id = room_id
	_expected_leader_token = leader_token
	Net.start_server(room_id, capacity)
	_idle_timer.start()


## Releases whatever this instance is currently doing: the host kills its server process,
## the server quits, and everyone else just drops the network connection.
func leave() -> void:
	if _is_dedicated_server:
		get_tree().quit()
		return

	_leaving = true
	_server_process.kill()
	if Net.is_connected:
		Net.stop_net()
	_reset()


## Called by the host's Start button. Only the leader may start, and only once.
func request_start() -> void:
	if _game_started or not is_leader():
		return

	if Net.is_server:
		_begin_start()
	else:
		rpc_request_start_game.rpc_id(Net.SERVER_ID)


## True when the local machine is the session's host (the player who created it).
func is_leader() -> bool:
	return _leader_peer != 0 and _leader_peer == multiplayer.get_unique_id()


func get_leader_peer() -> int:
	return _leader_peer


func get_room_id() -> String:
	return _room_id


func is_dedicated_server() -> bool:
	return _is_dedicated_server

#endregion


#region RPCs

## A client proves it spawned this server by presenting the one-time token.
@rpc("any_peer", "call_remote", "reliable")
func rpc_claim_leader(token: String) -> void:
	if not Net.is_server or _leader_peer != 0:
		return
	if token.is_empty() or token != _expected_leader_token:
		return
	_set_leader(multiplayer.get_remote_sender_id())


## Clients that joined later ask for the current host so their UI can show it.
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_leader_state() -> void:
	if not Net.is_server:
		return
	rpc_leader_changed.rpc_id(multiplayer.get_remote_sender_id(), _leader_peer)


@rpc("authority", "call_local", "reliable")
func rpc_leader_changed(leader_peer_id: int) -> void:
	_leader_peer = leader_peer_id
	leader_changed.emit(leader_peer_id)
	if _leader_peer != 0:
		_leader_sync_timer.stop()
		_idle_timer.stop()


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_start_game() -> void:
	if not Net.is_server:
		return
	if multiplayer.get_remote_sender_id() != _leader_peer:
		return
	_begin_start()

#endregion


#region Internal - server

func _set_leader(peer_id: int) -> void:
	if peer_id == 0:
		return
	# call_local keeps the server's own copy of _leader_peer in sync.
	rpc_leader_changed.rpc(peer_id)


func _begin_start() -> void:
	if _game_started:
		return
	_game_started = true
	starting_game.emit()
	Net.server_set_accepting_new_connections(false)
	if Main.instance:
		Main.instance.rpc_start_loading.rpc()


func _on_peer_connected(id: int) -> void:
	if not Net.is_server:
		return
	# ENET dev path has no leader token: the first peer in becomes the host.
	if _leader_peer == 0 and _expected_leader_token.is_empty():
		_set_leader(id)


func _on_peer_disconnected(id: int) -> void:
	if not Net.is_server:
		return
	if id == _leader_peer:
		push_warning("Lobby: host %d left, shutting down server" % id)
		get_tree().quit()


func _on_idle_timeout() -> void:
	if Net.is_server and _leader_peer == 0:
		push_warning("Lobby: no host claimed the server in time, shutting down")
		get_tree().quit()

#endregion


#region Internal - client

func _on_joined_game() -> void:
	_creating = false
	_stop_waiting_for_room()
	_leader_sync_attempts = 0
	lobby_joined.emit()
	_leader_sync_timer.start()


func _on_join_failed() -> void:
	if not _creating:
		lobby_failed.emit("Failed to join lobby")
		return

	if _join_retries >= MAX_JOIN_RETRIES:
		_fail_create("Failed to join the game server")
		return

	_join_retries += 1
	await get_tree().create_timer(JOIN_RETRY_DELAY).timeout
	if _creating and not Net.is_connected:
		Net.start_joining_game(_room_id)


func _on_connection_closed() -> void:
	if _is_dedicated_server:
		# A server without a room is useless; fail fast so the spawning client stops waiting.
		push_warning("Lobby: dedicated server lost its signaling connection, shutting down")
		get_tree().quit()
		return
	if _leaving or _creating:
		return
	_leader_sync_timer.stop()
	_server_process.kill()
	lobby_failed.emit("Connection closed")
	_reset()


## Re-asserts leadership until the server acknowledges it, or asks for the current host
## once. Retrying covers the window before the WebRTC peer link is actually up, since
## early RPCs are silently dropped.
func _sync_leader() -> void:
	if not Net.is_connected or Net.is_server:
		_leader_sync_timer.stop()
		return
	if _leader_peer != 0:
		_leader_sync_timer.stop()
		return

	_leader_sync_attempts += 1
	if _leader_sync_attempts > MAX_LEADER_SYNC_ATTEMPTS:
		_leader_sync_timer.stop()
		return

	if _pending_leader_token.is_empty():
		rpc_request_leader_state.rpc_id(Net.SERVER_ID)
	else:
		rpc_claim_leader.rpc_id(Net.SERVER_ID, _pending_leader_token)

#endregion


#region Internal - create handshake

## Watches the signaling lobby feed until the spawned server publishes its room, then
## joins it. Avoids hammering signaling with join attempts while the child boots.
func _start_waiting_for_room() -> void:
	_waiting_for_room = true
	SimpleWebRTC.signaling_server_url = Net.SIGNALING_SERVER_URL
	SimpleWebRTC.game_id = Net.GAME_ID
	SimpleWebRTC.disconnect_lobby_feed()

	if not SimpleWebRTC.lobby_snapshot_received.is_connected(_on_wait_lobby_update):
		SimpleWebRTC.lobby_snapshot_received.connect(_on_wait_lobby_update)
	if not SimpleWebRTC.lobby_list_received.is_connected(_on_wait_lobby_update):
		SimpleWebRTC.lobby_list_received.connect(_on_wait_lobby_update)
	if not SimpleWebRTC.lobby_error.is_connected(_on_wait_lobby_error):
		SimpleWebRTC.lobby_error.connect(_on_wait_lobby_error)

	if SimpleWebRTC.connect_lobby_feed() != OK:
		_fail_create("Could not reach the lobby service")
		return

	SimpleWebRTC.subscribe_lobbies()
	_room_wait_timer.start()


func _stop_waiting_for_room() -> void:
	_room_wait_timer.stop()
	if not _waiting_for_room:
		return
	_waiting_for_room = false

	if SimpleWebRTC.lobby_snapshot_received.is_connected(_on_wait_lobby_update):
		SimpleWebRTC.lobby_snapshot_received.disconnect(_on_wait_lobby_update)
	if SimpleWebRTC.lobby_list_received.is_connected(_on_wait_lobby_update):
		SimpleWebRTC.lobby_list_received.disconnect(_on_wait_lobby_update)
	if SimpleWebRTC.lobby_error.is_connected(_on_wait_lobby_error):
		SimpleWebRTC.lobby_error.disconnect(_on_wait_lobby_error)

	SimpleWebRTC.unsubscribe_lobbies()
	SimpleWebRTC.disconnect_lobby_feed()


func _on_wait_lobby_update(lobbies: Array[Dictionary]) -> void:
	if not _waiting_for_room:
		return
	for lobby: Dictionary in lobbies:
		if _room_id_from(lobby) == _room_id:
			_stop_waiting_for_room()
			_join_retries = 0
			if Net.start_joining_game(_room_id) != OK:
				_fail_create("Failed to start join")
			return


func _on_wait_lobby_error(reason: String) -> void:
	if not _waiting_for_room:
		return
	_fail_create("Lobby service error: %s" % reason)


func _on_room_wait_timeout() -> void:
	if _creating:
		_fail_create("The game server did not start in time")


func _fail_create(reason: String) -> void:
	_creating = false
	_server_process.kill()
	_reset()
	lobby_failed.emit(reason)


func _room_id_from(lobby: Dictionary) -> String:
	for key: String in ["room_id", "roomId", "room", "id"]:
		if lobby.has(key):
			return str(lobby.get(key, "")).strip_edges()
	return ""

#endregion


#region Helpers

func _reset() -> void:
	_stop_waiting_for_room()
	_creating = false
	_leaving = false
	_game_started = false
	_room_id = ""
	_leader_peer = 0
	_expected_leader_token = ""
	_pending_leader_token = ""
	_leader_sync_attempts = 0
	_join_retries = 0
	_leader_sync_timer.stop()
	_idle_timer.stop()


func _generate_token() -> String:
	return "%x%x" % [randi(), Time.get_ticks_usec()]

#endregion
