class_name Police
extends Npc
## Police officer NPC. Server-simulated like every Npc. It watches for wanted players
## (vision cone + line of sight), chases them, beats them down with a baton and, once
## the suspect is ragdolled and within reach, arrests them: CrimeManager confiscates
## their belongings and the target client is escorted to a free jail cell.

enum State { IDLE, CHASE, ATTACK, ESCORT, RETURN }

const BATON_SCENE := preload("res://src/features/items/data/police_baton/police_baton_equip.tscn")

@export_group("Perception")
## Maximum distance a suspect can be spotted at.
@export var vision_range := 20.0
## Full cone angle (degrees) the officer can see within.
@export var vision_angle_deg := 80.0
## How long the officer keeps chasing after losing sight of the suspect.
@export var lose_sight_grace := 3.0

@export_group("Combat")
## Distance at which the officer stops and swings the baton.
@export var attack_range := 1.8
## Seconds between baton swings.
@export var attack_cooldown := 1.2
## Distance at which a ragdolled suspect can be cuffed.
@export var arrest_range := 2.0

@export_group("Movement")
## Speed multiplier while chasing/escorting.
@export var chase_speed_multiplier := 1.3
## How close to the post counts as arrived.
@export var return_arrive_distance := 1.5

var _state: State = State.IDLE
var _target: Player = null
var _attack_timer := 0.0
var _lost_sight_timer := 0.0
var _spawn_position := Vector3.ZERO
var _nav_agent: NavigationAgent3D = null
var _baton: MeleeEquip = null


func _ready() -> void:
	super()
	_spawn_position = global_position
	_baton = equipment.get_equipped_node() as MeleeEquip
	if _baton != null:
		# The NPC is server-local; make sure the host's input never swings its baton.
		_baton.set_process_unhandled_input(false)

	_nav_agent = NavigationAgent3D.new()
	_nav_agent.path_desired_distance = 0.5
	_nav_agent.target_desired_distance = 1.0
	_nav_agent.radius = 0.4
	add_child(_nav_agent)


func _mount_default_equipment() -> void:
	if equipment:
		equipment.mount_scene(BATON_SCENE)


## Crime label used when a player assaults this officer.
func get_crime_label() -> String:
	return "an officer"


func _update_locomotion() -> void:
	if not is_local:
		return

	var delta := get_physics_process_delta_time()
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	_update_target(delta)

	match _state:
		State.CHASE, State.ATTACK:
			_do_chase()
		State.ESCORT:
			_do_escort()
		State.RETURN:
			_do_return()
		_:
			locomotion.desired_direction = Vector3.ZERO
			locomotion.run_requested = false
			move_speed_multiplier = 1.0


## Picks the nearest wanted player the officer can see, or gives up after the grace.
func _update_target(delta: float) -> void:
	if _state == State.ESCORT:
		return
	if _target != null and (
			not is_instance_valid(_target) or CrimeManager.is_player_jailed(_target.player_id)
	):
		_target = null
		_state = State.RETURN

	var best: Player = null
	var best_distance := vision_range
	for candidate: Player in PlayerManager.get_player_nodes():
		if candidate == null or not is_instance_valid(candidate):
			continue
		if not CrimeManager.is_player_wanted(candidate.player_id):
			continue
		if CrimeManager.is_player_jailed(candidate.player_id) or candidate.arrested:
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance > vision_range or not _can_see(candidate):
			continue
		if distance < best_distance:
			best = candidate
			best_distance = distance

	if best != null:
		_target = best
		_lost_sight_timer = lose_sight_grace
		if _state != State.ATTACK:
			_state = State.CHASE
	elif _target != null:
		_lost_sight_timer -= delta
		if _lost_sight_timer <= 0.0:
			_target = null
			_state = State.RETURN


## Vision cone test plus a line-of-sight raycast to the suspect's body.
func _can_see(candidate: Player) -> bool:
	var to_target := candidate.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() > 0.001:
		var forward := -global_transform.basis.z
		forward.y = 0.0
		var angle := rad_to_deg(acos(clampf(forward.normalized().dot(to_target.normalized()), -1.0, 1.0)))
		if angle > vision_angle_deg * 0.5:
			return false

	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0.0, 1.5, 0.0),
		candidate.global_position + Vector3(0.0, 1.0, 0.0),
		1 | 2,
	)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.get("collider") == candidate


func _do_chase() -> void:
	if _target == null:
		_state = State.RETURN
		return

	var distance := global_position.distance_to(_target.global_position)
	if _target.is_ragdolled and distance <= arrest_range:
		_arrest()
		return
	if distance <= attack_range and not _target.is_ragdolled:
		_state = State.ATTACK
		move_speed_multiplier = 1.0
		locomotion.desired_direction = Vector3.ZERO
		locomotion.run_requested = false
		_face(_target.global_position - global_position)
		_try_attack()
		return

	_state = State.CHASE
	move_speed_multiplier = chase_speed_multiplier
	locomotion.run_requested = true
	_navigate_to(_target.global_position)


## Follows the arrested suspect to the station.
func _do_escort() -> void:
	if _target == null or not is_instance_valid(_target) or CrimeManager.is_player_jailed(_target.player_id):
		_target = null
		_state = State.RETURN
		return

	var distance := global_position.distance_to(_target.global_position)
	if distance > 2.5:
		move_speed_multiplier = chase_speed_multiplier
		locomotion.run_requested = true
		_navigate_to(_target.global_position)
	else:
		move_speed_multiplier = 1.0
		locomotion.desired_direction = Vector3.ZERO
		locomotion.run_requested = false
		_face(_target.global_position - global_position)


func _do_return() -> void:
	move_speed_multiplier = 1.0
	locomotion.run_requested = false
	if global_position.distance_to(_spawn_position) <= return_arrive_distance:
		_state = State.IDLE
		locomotion.desired_direction = Vector3.ZERO
		return
	_navigate_to(_spawn_position)


## Hands the ragdolled suspect over to CrimeManager (confiscation + escort).
func _arrest() -> void:
	if _target == null:
		return
	_state = State.ESCORT
	move_speed_multiplier = 1.0
	locomotion.desired_direction = Vector3.ZERO
	locomotion.run_requested = false
	CrimeManager.arrest_player(_target.player_id)


func _try_attack() -> void:
	if _baton == null or _attack_timer > 0.0:
		return
	if _target == null or _target.is_ragdolled:
		return
	if _baton.try_attack():
		_attack_timer = attack_cooldown


## Steers toward [param position] using the navmesh agent, falling back to direct
## steering when there is no agent or it yields no usable direction (e.g. off-mesh).
func _navigate_to(position: Vector3) -> void:
	var direction := Vector3.ZERO
	if _nav_agent != null:
		_nav_agent.target_position = position
		direction = _nav_agent.get_next_path_position() - global_position
		direction.y = 0.0
	if direction.length_squared() < 0.001:
		direction = position - global_position
		direction.y = 0.0
	locomotion.desired_direction = direction.normalized()
	_face(direction)


## Rotates the officer to face a world-space direction.
func _face(direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		return
	rotation.y = atan2(-direction.x, -direction.z)
