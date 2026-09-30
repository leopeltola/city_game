class_name Guard
extends Npc
## Guard NPC stationed in a building. Server-simulated like every Npc. It walks a
## patrol route while idle and watches a designated [member guard_area]: when a player
## commits a crime inside that area and the guard sees it (vision cone + line of
## sight), the guard aggros, chases them down and fights with bare fists. It disengages
## as soon as the suspect leaves the guarded area (or is lost from sight for too long)
## and returns to its post.
##
## Unlike [Police] it does not arrest suspects: it only drives them out of its zone.

enum State { IDLE, CHASE, ATTACK, RETURN }

## When true, logs the guard's aggro decisions to the server console. Turn off once
## guards behave as expected.
const DEBUG := true

@export_group("Guard Zone")
## The area this guard watches. A player committing a crime inside it (assault, theft,
## ...) is noticed when the guard can see them. Usually assigned by [GuardSpawner].
## The area needs monitoring on and its collision mask set to the player layer (2).
@export var guard_area: Area3D = null

@export_group("Perception")
## Maximum distance a suspect can be spotted at.
@export var vision_range := 20.0
## Full cone angle (degrees) the guard can see within.
@export var vision_angle_deg := 80.0
## How long the guard keeps chasing after losing sight of the suspect.
@export var lose_sight_grace := 3.0

@export_group("Combat")
## Distance at which the guard stops and throws a punch.
@export var attack_range := 1.8
## Seconds between punches.
@export var attack_cooldown := 1.2

@export_group("Movement")
## Speed multiplier while chasing.
@export var chase_speed_multiplier := 1.0
## How close to the post counts as arrived.
@export var return_arrive_distance := 1.5

@export_group("Patrol")
## Optional path the guard walks point to point while idle. Leave empty to just stand at
## its spawn position. Read in world space, so it can be a level [Path3D].
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
var _fists: MeleeEquip = null
## Players currently inside the guarded area, keyed by player_id. Server only.
var _occupants: Dictionary[int, Player] = {}
## Cached patrol data, rebuilt lazily when the assigned route changes.
var _patrol_curve: Curve3D = null
var _patrol_point_count := 0
## Index of the patrol point currently being walked to.
var _patrol_index := 0
## Seconds spent without making progress toward the current patrol point.
var _patrol_stuck_time := 0.0
## Closest this guard has gotten to the current patrol point.
var _patrol_best_distance := INF


func _ready() -> void:
	super()
	add_to_group("guard")
	_spawn_position = global_position
	if equipment != null:
		_fists = equipment.get_equipped_node() as MeleeEquip
	if _fists != null:
		# The NPC is server-local; make sure the host's input never throws a punch.
		_fists.set_process_unhandled_input(false)
	if not is_local:
		return
	if _fists == null:
		push_warning("Guard '%s' has no melee equip mounted; it will chase but never punch." % name)
	if guard_area == null:
		push_warning("Guard '%s' has no guard_area; it will react anywhere it can see." % name)
	else:
		# The guard owns its zone: make sure the area detects players no matter how it
		# was authored in the scene (a fresh Area3D masks layer 1, not the player layer).
		guard_area.monitoring = true
		guard_area.set_collision_mask_value(2, true)
		guard_area.body_entered.connect(_on_area_body_entered)
		guard_area.body_exited.connect(_on_area_body_exited)
		_seed_occupants.call_deferred()
	CrimeManager.crime_committed.connect(_on_crime_committed)
	_log("ready: area=%s fists=%s" % [guard_area, _fists])


## Logs a decision to the server console when [constant DEBUG] is on.
func _log(message: String) -> void:
	if DEBUG:
		print("[Guard %s] %s" % [name, message])


## Picks up players already inside the zone when the guard connects, so a guard
## spawning on top of someone still reacts.
func _seed_occupants() -> void:
	if guard_area == null:
		return
	await get_tree().physics_frame
	for body: Node3D in guard_area.get_overlapping_bodies():
		_on_area_body_entered(body)


## Crime label used when a player assaults this guard.
func get_crime_label() -> String:
	return "a guard"


## Tracks players entering the guarded area so crime/disengage checks can use membership.
func _on_area_body_entered(body: Node3D) -> void:
	if body is Player:
		_occupants[body.player_id] = body


func _on_area_body_exited(body: Node3D) -> void:
	if body is Player:
		_occupants.erase(body.player_id)


## Reacts to a crime recorded on the server: aggros only when the culprit is inside the
## guarded area and currently visible.
func _on_crime_committed(player_id: int, _label: String) -> void:
	if not is_local or _target != null:
		return
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if player == null or not is_instance_valid(player):
		_log("crime by %s ignored: no player node" % player_id)
		return
	if not _is_in_area(player):
		_log("crime by %s ignored: outside area" % player_id)
		return
	if not _can_see(player):
		_log("crime by %s ignored: no line of sight" % player_id)
		return
	_log("aggro on %s (witnessed '%s')" % [player_id, _label])
	_aggro(player)


## Guards also turn on whoever attacks them, even from outside the vision cone.
func _on_hit_received(damage: float, attacker_id: int = 0) -> void:
	super(damage, attacker_id)
	if not is_local or attacker_id <= 0:
		return
	var attacker: Player = PlayerManager.get_player_node_by_id(attacker_id)
	if attacker == null or not is_instance_valid(attacker):
		return
	_face(attacker.global_position - global_position)
	_log("attacked by %s: aggro" % attacker_id)
	_aggro(attacker)


## Sets [param player] as the suspect and starts the chase.
func _aggro(player: Player) -> void:
	_target = player
	_lost_sight_timer = lose_sight_grace
	if _state != State.ATTACK:
		_state = State.CHASE


func _update_locomotion() -> void:
	if not is_local:
		return

	var delta := get_physics_process_delta_time()
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	_update_target(delta)

	match _state:
		State.CHASE, State.ATTACK:
			_do_chase()
		State.RETURN:
			_do_return()
		_:
			_do_idle()


## Drops the target once it leaves the guarded area, is downed, or has been out of
## sight past the grace period.
func _update_target(delta: float) -> void:
	if _target == null:
		return
	if not is_instance_valid(_target) or _target.arrested or not _is_in_area(_target):
		_drop_target()
		return
	if _can_see(_target):
		_lost_sight_timer = lose_sight_grace
	else:
		_lost_sight_timer -= delta
		if _lost_sight_timer <= 0.0:
			_drop_target()


func _drop_target() -> void:
	_target = null
	_state = State.RETURN


## True while [param player] is inside the guarded area. With no area assigned the guard
## watches everywhere (and warns about it on ready).
func _is_in_area(player: Player) -> bool:
	if guard_area == null:
		return true
	return _occupants.has(player.player_id)


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
	if _target.is_ragdolled:
		# Suspect is down: hold position over them, but stop swinging.
		move_speed_multiplier = 1.0
		locomotion.desired_direction = Vector3.ZERO
		locomotion.run_requested = false
		_face(_target.global_position - global_position)
		return
	if distance <= attack_range:
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


## Index of the patrol point closest to the guard's current position.
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


## True once the guard has stalled on [param distance] to the current point for
## [member patrol_stuck_timeout], so an unreachable point doesn't block the route.
func _patrol_gave_up(distance: float) -> bool:
	if distance < _patrol_best_distance - 0.1:
		_patrol_best_distance = distance
		_patrol_stuck_time = 0.0
	else:
		_patrol_stuck_time += get_physics_process_delta_time()
	return _patrol_stuck_time >= patrol_stuck_timeout


func _try_attack() -> void:
	if _fists == null and equipment != null:
		_fists = equipment.get_equipped_node() as MeleeEquip
	if _fists == null or _attack_timer > 0.0:
		return
	if _target == null or _target.is_ragdolled:
		return
	if _fists.try_attack():
		_attack_timer = attack_cooldown
