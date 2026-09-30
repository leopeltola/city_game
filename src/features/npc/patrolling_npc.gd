class_name PatrollingNpc
extends Npc
## Shared base for server-simulated NPCs that walk a patrol route and chase a suspect
## they can see. Owns the patrol route, the vision cone + line-of-sight test, the
## aggro / lose-sight bookkeeping and the idle / return / chase locomotion.
##
## Subclasses only decide [i]who[/i] is a valid suspect and what happens when that
## suspect is at attack range or down:
##  - [method _find_suspect] / [method _is_target_valid] pick the target (Police scans
##    for wanted players; Guard only reacts to crimes and hits).
##  - [method _attack_weapon] / [method _on_target_down] define the combat response.
##  - [method _on_pre_locomotion] hooks any extra per-frame work (e.g. Police key renewal).

## AI states. ESCORT is only used by subclasses that escort an arrested suspect.
enum State { IDLE, CHASE, ATTACK, ESCORT, RETURN }

@export_group("Perception")
## Maximum distance a suspect can be spotted at.
@export var vision_range := 20.0
## Full cone angle (degrees) the NPC can see within.
@export var vision_angle_deg := 80.0
## How long the NPC keeps chasing after losing sight of the suspect.
@export var lose_sight_grace := 3.0

@export_group("Combat")
## Distance at which the NPC stops and attacks.
@export var attack_range := 1.8
## Seconds between attacks.
@export var attack_cooldown := 1.2

@export_group("Movement")
## Speed multiplier while chasing/escorting.
@export var chase_speed_multiplier := 1.0
## How close to the post counts as arrived.
@export var return_arrive_distance := 1.5

@export_group("Patrol")
## Optional path the NPC loops around while idle. Leave empty to just stand at its
## spawn position. Read in world space, so it can be a level [Path3D].
@export var patrol_route: Path3D = null
## How close to a patrol point counts as reached before heading to the next one.
@export var patrol_arrive_distance := 1.5
## Seconds without getting closer to a patrol point before skipping it, so a point that
## sits off the navmesh can't stall the route forever.
@export var patrol_stuck_timeout := 3.0

var _state: State = State.IDLE
var _target: Player = null
var _attack_timer := 0.0
var _lost_sight_timer := 0.0
var _spawn_position := Vector3.ZERO
## Cached patrol data, rebuilt lazily when the assigned route changes.
var _patrol_curve: Curve3D = null
var _patrol_point_count := 0
## Index of the patrol point currently being walked to.
var _patrol_index := 0
## Seconds spent without making progress toward the current patrol point.
var _patrol_stuck_time := 0.0
## Closest this NPC has gotten to the current patrol point.
var _patrol_best_distance := INF


func _ready() -> void:
	super()
	_spawn_position = global_position


func _update_locomotion() -> void:
	if not is_local:
		return

	var delta := get_physics_process_delta_time()
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	_on_pre_locomotion(delta)
	_update_target(delta)

	match _state:
		State.CHASE, State.ATTACK:
			_do_chase()
		State.ESCORT:
			_do_escort()
		State.RETURN:
			_do_return()
		_:
			_do_idle()


## Virtual: extra per-frame work before target/locomotion updates (e.g. Police renewing
## its jail key). Called only on the local (server) peer.
func _on_pre_locomotion(_delta: float) -> void:
	pass


# --- Targeting ---


## Acquires or keeps the current suspect. A target that stops being valid is dropped;
## otherwise an unseen target expires after [member lose_sight_grace]. See also
## [method _find_suspect] for subclasses that acquire proactively.
func _update_target(delta: float) -> void:
	if _state == State.ESCORT:
		return

	if _target != null:
		if not _is_target_valid(_target):
			_drop_target()
			return
		if _has_sight(_target):
			_lost_sight_timer = lose_sight_grace
		else:
			_lost_sight_timer -= delta
			if _lost_sight_timer <= 0.0:
				_drop_target()
				return

	var best := _find_suspect()
	if best != null:
		_aggro(best)


## Sets [param player] as the suspect and starts the chase.
func _aggro(player: Player) -> void:
	_target = player
	_lost_sight_timer = lose_sight_grace
	if _state != State.ATTACK:
		_state = State.CHASE


func _drop_target() -> void:
	_target = null
	_state = State.RETURN


## Virtual: whether [param target] is still worth chasing (wanted, in-zone, alive, ...).
func _is_target_valid(target: Player) -> bool:
	return is_instance_valid(target)


## Virtual: the nearest suspect the NPC can see, or null to never acquire on its own.
func _find_suspect() -> Player:
	return null


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


## Virtual: whether the target is currently in view, which refreshes the lose-sight
## grace. Defaults to the vision cone alone; subclasses can add their own range gate.
func _has_sight(target: Player) -> bool:
	return _can_see(target)


# --- Movement ---


## Walks toward the suspect and hands off to [_on_target_down] when they are down or to
## [_try_attack] once they are in range.
func _do_chase() -> void:
	if _target == null:
		_state = State.RETURN
		return

	var distance := global_position.distance_to(_target.global_position)
	if _target.is_ragdolled and _on_target_down(distance):
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


## Virtual: reacts to a ragdolled suspect. Return true to stop for this frame (e.g.
## arrest or hold position); return false to keep chasing the body.
func _on_target_down(_distance: float) -> bool:
	move_speed_multiplier = 1.0
	locomotion.desired_direction = Vector3.ZERO
	locomotion.run_requested = false
	_face(_target.global_position - global_position)
	return true


## Virtual: escorts an arrested suspect. Base does nothing (only Police uses it).
func _do_escort() -> void:
	pass


func _do_return() -> void:
	move_speed_multiplier = 1.0
	locomotion.run_requested = false
	var post := _spawn_position
	if _patrol_active():
		_set_patrol_index(_closest_patrol_point())
		post = _patrol_waypoint(_patrol_index)
	if global_position.distance_to(post) <= return_arrive_distance:
		_state = State.IDLE
		locomotion.desired_direction = Vector3.ZERO
		return
	_navigate_to(post)


## Stands still, or walks the patrol route point by point when one is assigned.
func _do_idle() -> void:
	move_speed_multiplier = 1.0
	locomotion.run_requested = false
	if not _patrol_active():
		locomotion.desired_direction = Vector3.ZERO
		return

	var target := _patrol_waypoint(_patrol_index)
	var distance := global_position.distance_to(target)
	if distance <= patrol_arrive_distance or _patrol_gave_up(distance):
		_set_patrol_index((_patrol_index + 1) % _patrol_point_count)
		target = _patrol_waypoint(_patrol_index)
	_navigate_to(target)


## Attacks the current target when it is in range and off cooldown. The weapon is
## supplied by [_attack_weapon] so the same timing/cooling works for batons and fists.
func _try_attack() -> void:
	if _attack_timer > 0.0:
		return
	if _target == null or _target.is_ragdolled:
		return
	var weapon := _attack_weapon()
	if weapon != null and weapon.try_attack():
		_attack_timer = attack_cooldown


## Virtual: the melee weapon to swing, or null if the NPC has no weapon mounted.
func _attack_weapon() -> MeleeEquip:
	return null


# --- Patrol ---


## True when a usable patrol route is assigned, refreshing the cached curve/points
## when the route's curve changes.
func _patrol_active() -> bool:
	if patrol_route == null or not is_instance_valid(patrol_route):
		return false
	if _patrol_curve != patrol_route.curve:
		_patrol_curve = patrol_route.curve
		_patrol_point_count = _patrol_curve.get_point_count() if _patrol_curve != null else 0
		_set_patrol_index(_closest_patrol_point())
	return _patrol_point_count >= 2


## Sets the patrol point being walked to and resets its progress tracking.
func _set_patrol_index(index: int) -> void:
	_patrol_index = index
	_patrol_stuck_time = 0.0
	_patrol_best_distance = INF


## Index of the patrol point closest to the NPC's current position.
func _closest_patrol_point() -> int:
	var best := 0
	var best_distance := INF
	for i in _patrol_point_count:
		var distance := global_position.distance_squared_to(_patrol_waypoint(i))
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


## World-space position of the patrol route point at [param index].
func _patrol_waypoint(index: int) -> Vector3:
	return patrol_route.to_global(_patrol_curve.get_point_position(index))


## True once the NPC has stalled at [param distance] from the current point for
## [member patrol_stuck_timeout], so an unreachable point doesn't block the route.
func _patrol_gave_up(distance: float) -> bool:
	if distance < _patrol_best_distance - 0.1:
		_patrol_best_distance = distance
		_patrol_stuck_time = 0.0
	else:
		_patrol_stuck_time += get_physics_process_delta_time()
	return _patrol_stuck_time >= patrol_stuck_timeout
