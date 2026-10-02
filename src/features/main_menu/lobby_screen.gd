extends MarginContainer

## Pre-game lobby screen: shows who is connected and gives the host the Start control.

signal leave_requested

## Player names replicate after the PlayerData spawn, so labels are refreshed in place
## on this interval while the screen is visible rather than only on player_added.
const ROSTER_REFRESH_INTERVAL := 0.5

@onready var room_name_label: Label = %RoomName
@onready var status_label: Label = %StatusLabel
@onready var player_list: VBoxContainer = %PlayerList
@onready var start_button: Button = %StartButton
@onready var leave_button: Button = %LeaveButton

var _rows: Dictionary[int, Label] = { }
var _refresh_timer: Timer


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	leave_button.pressed.connect(_on_leave_pressed)

	if Lobby.instance:
		Lobby.instance.leader_changed.connect(_on_leader_changed)
		Lobby.instance.starting_game.connect(_on_starting_game)

	PlayerManager.player_added.connect(_on_roster_changed)
	PlayerManager.player_left.connect(_on_roster_changed)
	visibility_changed.connect(_on_visibility_changed)

	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = ROSTER_REFRESH_INTERVAL
	_refresh_timer.timeout.connect(_rebuild_players)
	add_child(_refresh_timer)

	if is_visible_in_tree():
		_on_visibility_changed()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_refresh()
		_refresh_timer.start()
	else:
		_refresh_timer.stop()


func _on_roster_changed(_player_data: PlayerData = null) -> void:
	_rebuild_players()


func _on_leader_changed(_leader_peer_id: int) -> void:
	_rebuild_players()
	_update_controls()


func _on_starting_game() -> void:
	start_button.disabled = true
	status_label.text = "Starting game..."


func _on_start_pressed() -> void:
	start_button.disabled = true
	status_label.text = "Starting game..."
	if Lobby.instance:
		Lobby.instance.request_start()


func _on_leave_pressed() -> void:
	leave_requested.emit()


func _refresh() -> void:
	if Lobby.instance == null:
		return
	room_name_label.text = Lobby.instance.get_room_id()
	_rebuild_players()
	_update_controls()


func _update_controls() -> void:
	var leader := Lobby.instance.is_leader()
	start_button.visible = leader
	start_button.disabled = false
	if leader:
		status_label.text = "You are the host"
	else:
		status_label.text = "Waiting for the host to start..."


func _rebuild_players() -> void:
	if Lobby.instance == null:
		return

	var leader_peer := Lobby.instance.get_leader_peer()
	var current_peers: Array[int] = []

	for pd: PlayerData in PlayerManager.get_players():
		current_peers.append(pd.peer_id)
		var display_name := pd.player_name
		if pd.peer_id == leader_peer:
			display_name += "  (Host)"

		var row: Label = _rows.get(pd.peer_id)
		if row == null:
			row = Label.new()
			player_list.add_child(row)
			_rows[pd.peer_id] = row
		row.text = display_name

	for peer_id: int in _rows.keys():
		if peer_id in current_peers:
			continue
		var row: Label = _rows[peer_id]
		if is_instance_valid(row):
			row.queue_free()
		_rows.erase(peer_id)
