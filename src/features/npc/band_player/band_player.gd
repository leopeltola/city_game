class_name BandPlayer
extends Npc

enum STATE {
	RETURN,
	PLAY,
}

@export var playing_animation: String = ""
@export var arrival_distance: float = 0.5
@export var turn_speed: float = 12.0

@export var instrument: StaticMusicInstrument

@onready var navigation_agent: NavigationAgent3D = %NavigationAgent3D

var _state: STATE = STATE.PLAY
@onready var _home_position: Vector3 = global_position


func _ready() -> void:
	super._ready()
	_home_position = global_position
	
	# Configure navigation agent settings
	navigation_agent.target_desired_distance = arrival_distance
	navigation_agent.path_desired_distance = 0.5


func _update_locomotion(delta: float = get_physics_process_delta_time()) -> void:
	if not is_local:
		return

	# If displaced from home position, start pathfinding return
	if global_position.distance_to(_home_position) > arrival_distance and _state != STATE.RETURN:
		_state = STATE.RETURN
		navigation_agent.target_position = _home_position

	match _state:
		STATE.PLAY:
			_do_play(delta)
		STATE.RETURN:
			_do_return(delta)
		_:
			locomotion.desired_direction = Vector3.ZERO
			locomotion.run_requested = false
			move_speed_multiplier = 0.5


func _do_play(delta: float) -> void:
	locomotion.run_requested = false
	move_speed_multiplier = 0.01

	if is_instance_valid(instrument):
		var dir := instrument.global_position - global_position
		dir.y = 0.0
		locomotion.desired_direction = dir.normalized() if dir.length_squared() > 0.001 else Vector3.ZERO
		_face(instrument.get_facing_direction(), delta)
	else:
		locomotion.desired_direction = Vector3.ZERO


func _do_return(delta: float) -> void:
	# Stop returning if target position is reached or navigation is finished
	if navigation_agent.is_navigation_finished():
		_state = STATE.PLAY
		locomotion.desired_direction = Vector3.ZERO
		if is_instance_valid(instrument) and not instrument.animation_name.is_empty():
			_rpc_change_animation.rpc(instrument.animation_name)
		return

	var next_path_position: Vector3 = navigation_agent.get_next_path_position()
	var dir := global_position.direction_to(next_path_position)
	dir.y = 0.0

	if dir.length_squared() > 0.001:
		dir = dir.normalized()
		locomotion.desired_direction = dir
		_face(dir, delta) # Smoothly turn towards travel direction
	else:
		locomotion.desired_direction = Vector3.ZERO

	locomotion.run_requested = false
	move_speed_multiplier = 1.0


## Smoothly rotates the band player to face a world-space direction.
func _face(direction: Vector3, delta: float) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		return
	var target_angle := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_angle, delta * turn_speed)


@rpc("any_peer", "reliable", "call_local")
func _rpc_change_animation(new_animation: String) -> void:
	animator.play_action(new_animation, 0.1, 0.1)
