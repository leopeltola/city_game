class_name Vehicle
extends RigidBody3D
## Shared base for rideable physics vehicles: rider attachment, the single
## controller model (the rider's peer simulates the vehicle, the server does while
## it is parked) and the state replication that keeps every other peer eased
## toward the controller.
##
## Subclasses override [method _physics_process] and [method _unhandled_input] to
## add their own controls and must call super() in both so rider handling and
## replication keep working.

const SERVER_ID := 1

@export var sync_interval: float = 1.0 / 30.0
## How quickly a remote vehicle converges on the broadcast state.
@export var correction_speed: float = 12.0

var rider_id: int = 0 # player_id; 0 = no one
var has_rider: bool:
	get:
		return rider_id != 0

## Latest state from the controller: written locally by it, received by everyone
## else and eased toward in _follow.
var net_position: Vector3
var net_rotation: Vector3
var net_linear_velocity: Vector3
var net_angular_velocity: Vector3
var has_net := false
var _send_timer := 0.0


func _ready() -> void:
	# Keep simulating so a parked vehicle doesn't fall asleep on remote peers.
	can_sleep = false
	net_position = global_position
	net_rotation = global_rotation


func _physics_process(delta: float) -> void:
	if _is_controller():
		_publish(delta)
	else:
		_follow(delta)


func _unhandled_input(event: InputEvent) -> void:
	# Only the rider's peer may dismount.
	if has_rider and _is_controller() and event.is_action_pressed("e"):
		_stop_riding()


# The peer that simulates the vehicle: the rider's peer while ridden, otherwise
# the server. Exactly one peer satisfies this, so peers never fight over it.
func _is_controller() -> bool:
	if rider_id > 0:
		var data := PlayerManager.get_player_by_id(rider_id)
		return data != null and data.peer_id == multiplayer.get_unique_id()
	return Net.is_server


# Captures the state and forwards it on an interval. A client hands its state to
# the server, which relays it on to the other clients.
func _publish(delta: float) -> void:
	net_position = global_position
	net_rotation = global_rotation
	net_linear_velocity = linear_velocity
	net_angular_velocity = angular_velocity

	_send_timer += delta
	if _send_timer < sync_interval or multiplayer.multiplayer_peer == null:
		return
	_send_timer = 0.0
	_rpc_sync_state.rpc(net_position, net_rotation, net_linear_velocity, net_angular_velocity)


# Eases toward the latest state and coasts at the broadcast velocity.
func _follow(delta: float) -> void:
	if not has_net:
		return
	var k := 1.0 - exp(-correction_speed * delta)
	global_position = global_position.lerp(net_position, k)
	global_basis = global_basis.slerp(Basis.from_euler(net_rotation), k)
	linear_velocity = net_linear_velocity
	angular_velocity = net_angular_velocity


## The rider's player node, or null while parked.
func get_rider() -> Player:
	if rider_id == 0:
		return null
	return PlayerManager.get_player_node_by_id(rider_id)


func get_prompt(player_id: int) -> String:
	return "Ride" if not has_rider else ""


func can_interact(player_id: int) -> bool:
	return not has_rider


func interact(player_id: int) -> void:
	_start_riding(player_id)


func _start_riding(rider: int) -> void:
	var player := PlayerManager.get_player_node_by_id(rider)
	if not player:
		return
	%RemoteTransform3D.remote_path = player.get_path()
	player.in_vehicle = true
	_rpc_set_rider.rpc(rider)


func _stop_riding() -> void:
	var player := get_rider()
	%RemoteTransform3D.remote_path = ""
	if player:
		player.in_vehicle = false
		# The RemoteTransform3D forced the vehicle's full tilt onto the rider, so
		# level them back to a yaw-only rotation or they stand up skewed.
		player.global_rotation = Vector3(0.0, global_rotation.y, 0.0)
	_rpc_set_rider.rpc(0)


# Applies a state from the network. The server relays a client's state so the
# other clients receive it too; the controller ignores its own echo.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_sync_state(pos: Vector3, rot: Vector3, lin: Vector3, ang: Vector3) -> void:
	if not _is_controller():
		net_position = pos
		net_rotation = rot
		net_linear_velocity = lin
		net_angular_velocity = ang
		has_net = true
	if multiplayer.is_server():
		_rpc_sync_state.rpc(pos, rot, lin, ang)


@rpc("any_peer", "call_local", "reliable")
func _rpc_set_rider(player_id: int) -> void:
	# player_id may be 0, which means no-one -> server simulates it
	var net_id := SERVER_ID
	if player_id > 0:
		var data := PlayerManager.get_player_by_id(player_id)
		if data:
			net_id = data.peer_id # player net id
	rider_id = player_id
	set_multiplayer_authority(net_id)
