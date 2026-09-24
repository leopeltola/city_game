class_name BandPlayer
extends Npc

enum STATE {
	RETURN,
	PLAY,
}

@export var playing_animation: String = ""
@export var arrival_distance: float = 0.5

@onready var navigation_agent: NavigationAgent3D = %NavigationAgent3D

var _state: STATE = STATE.PLAY
@onready var _home_position: Vector3 = global_position

var instrument : StaticMusicInstrument

func _ready() -> void:
	super._ready()
	_home_position = global_position
	
	var instruments = get_tree().get_nodes_in_group("static_music_instrument")
	
	var picked_instrument = instruments.pick_random()
	picked_instrument.remove_from_group("static_music_instrument")
	instrument = picked_instrument
	
	# Configure navigation agent settings
	navigation_agent.target_desired_distance = arrival_distance
	navigation_agent.path_desired_distance = 0.5


func _update_locomotion() -> void:
	if not is_local:
		return

	# If displaced from home position, start pathfinding return
	if global_position.distance_to(_home_position) > arrival_distance and _state != STATE.RETURN:
		_state = STATE.RETURN
		navigation_agent.target_position = _home_position

	match _state:
		STATE.PLAY:
			_do_play()
		STATE.RETURN:
			_do_return()
		_:
			locomotion.desired_direction = Vector3.ZERO
			locomotion.run_requested = false
			move_speed_multiplier = 1.0


func _do_play() -> void:
	locomotion.desired_direction = Vector3.ZERO
	locomotion.run_requested = false
	move_speed_multiplier = 0.01
	
	var dir := instrument.global_position - global_position
	locomotion.desired_direction = dir.normalized()
	
	
	if instrument:
		_face(instrument.get_facing_direction())
	


@rpc("any_peer","reliable","call_local")
func _rpc_change_animation(new_animation):
	animator.play_action(new_animation, 0.1, 0.1)


func _do_return() -> void:
	# Stop returning if target position is reached or navigation is finished
	if navigation_agent.is_navigation_finished():
		_state = STATE.PLAY
		if instrument.animation_name:
			_rpc_change_animation.rpc(instrument.animation_name)
		return

	var next_path_position: Vector3 = navigation_agent.get_next_path_position()
	var dir := global_position.direction_to(next_path_position)
	dir.y = 0.0 # Keep direction aligned to ground plane

	locomotion.desired_direction = dir.normalized()
	locomotion.run_requested = false
	move_speed_multiplier = 1.0

## Rotates the band player to face a world-space direction.
func _face(direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		return
	rotation.y = atan2(-direction.x, -direction.z)
