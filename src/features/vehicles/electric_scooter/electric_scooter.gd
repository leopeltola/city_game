class_name ElectricScooter
extends Vehicle
## A self-balancing electric scooter. The rider steers by moving the mouse, keeps
## their balance with A/D (helped along by a constant small self-righting torque)
## and ragdolls if they let it tip too far while on the ground or smash into a wall
## at speed. Driving into someone fast enough hurts and ragdolls them, and counts as
## assault. A flipped scooter can be righted by interacting with it.

@export_group("Riding")
## Forward force applied while the throttle is held.
@export var engine_force: float = 45.0
## Forward speed the engine will not push past.
@export var max_speed: float = 14.0
## How strongly sideways velocity is cancelled while grounded. Higher grips more.
@export var lateral_grip: float = 14.0

@export_group("Steering")
## Radians of yaw per pixel of mouse movement.
@export var mouse_sensitivity: float = 0.003
## How hard the scooter turns toward the mouse direction.
@export var steer_strength: float = 25.0
## Damps the yaw so it does not overshoot the target.
@export var steer_damping: float = 3.0

@export_group("Balancing")
## Self-righting torque: the rider balancing themselves, always on.
@export var balance_strength: float = 5.0
## How fast roll/pitch velocity is bled off (1/s). Higher settles quicker.
@export var balance_damping: float = 6.0
## A/D torque used to lean the scooter (and catch a falling deck).
@export var lean_torque: float = 1.0

@export_group("Crash")
## Tilt past which the rider ragdolls while on the ground, in degrees.
@export var ragdoll_tilt_degrees: float = 55.0
## Fraction of the scooter's velocity thrown into the ragdoll on a crash.
@export var crash_force_scale: float = 0.6

@export_group("Impact Crash")
## Speed (m/s) the scooter must have before a wall hit can throw the rider off.
@export var crash_impact_speed: float = 4.0
## Speed (m/s) the scooter must be reduced to by the hit. This is what separates a
## real wall crash from a curb/crosswalk bump, which redirects the scooter but keeps
## it rolling.
@export var crash_stop_speed: float = 3.0
## How upright a surface normal may be before the hit counts as a ramp or the ground
## rather than a wall. 0 is a vertical wall, 1 is perfectly flat ground.
@export_range(0.0, 1.0) var crash_max_normal_up: float = 0.35

@export_group("Running Over")
## Minimum speed (m/s) at which driving into an actor hurts and ragdolls them. Below
## this the scooter simply passes through people.
@export var run_over_min_speed: float = 3.5
## Damage per m/s of impact speed.
@export var run_over_damage_per_speed: float = 3.0
## Damage cap, so a freak launch cannot one-shot everyone.
@export var run_over_max_damage: float = 60.0
## Multiplier converting impact speed into the ragdoll throw force.
@export var run_over_force_scale: float = 3.5
## Upward part of the throw, so the victim is flipped rather than only shoved.
@export var run_over_lift: float = 6.0
## Seconds before the same actor can be run into again by this scooter.
@export var run_over_cooldown: float = 0.75

@export_group("Feedback")
## Played to every peer where the scooter knocks someone over.
@export var run_over_sfx: AudioStream = preload("res://assets/sfx/punch_1.ogg")
## Played to every peer when a wall impact throws the rider off.
@export var crash_sfx: AudioStream = preload("res://assets/sfx/kenney_impacts/impactMetal_medium_000.ogg")

@export_group("Flipping")
## Tilt past which the scooter counts as flipped and rights itself on interaction.
@export var flipped_tilt_degrees: float = 55.0
## Upward impulse of the self-righting hop.
@export var flip_hop_impulse: float = 2.5
## How hard the self-righting torque pulls the scooter back upright.
@export var right_self_torque: float = 12.0
## Damps the self-righting torque.
@export var right_self_damping: float = 3.0
## How long the scooter keeps trying to right itself before giving up, in seconds.
@export var right_self_duration: float = 2.0

@onready var _runner_detector: ShapeCast3D = %RunnerDetector

var _target_yaw := 0.0
var _self_righting := false
var _self_right_time := 0.0
## Velocity from the previous _integrate_forces call. The change between calls is the
## last step's collision response, and the old value is the momentum before the hit.
var _last_integrate_velocity := Vector3.ZERO
var _has_last_integrate_velocity := false
## Set by an impact in _integrate_forces and consumed on the next physics frame.
var _pending_crash_velocity := Vector3.ZERO
var _has_pending_crash := false
## Guards against throwing the same rider twice while the dismount round-trip lands.
var _crash_cooldown := 0.0
## Actor instance id -> msec of the last run-over, so one pass hits once.
var _recent_run_overs: Dictionary[int, int] = {}
## Rider currently excluded from the runner sweep, so their own body never eats a hit.
var _detector_rider: Player = null


func _ready() -> void:
	super()
	# Needed for the ground check in _is_grounded and the impact contacts below.
	contact_monitor = true
	max_contacts_reported = 8
	_target_yaw = global_rotation.y


func _physics_process(delta: float) -> void:
	_crash_cooldown = maxf(_crash_cooldown - delta, 0.0)
	if not _is_controller():
		_has_pending_crash = false
		_pending_crash_velocity = Vector3.ZERO
	elif not has_rider:
		# A parked scooter still needs _apply_controls for its self-righting hop.
		_has_pending_crash = false
		_pending_crash_velocity = Vector3.ZERO
		_apply_controls(delta)
	elif _has_pending_crash:
		_has_pending_crash = false
		var throw_velocity := _pending_crash_velocity
		_pending_crash_velocity = Vector3.ZERO
		if crash_sfx:
			Audio.play_sfx_3d(crash_sfx, global_position, -3.0, 30.0, true)
		_crash(throw_velocity)
	else:
		_apply_controls(delta)
		_check_run_overs(delta)
	super(delta)


# Detects a hard collision with a wall (a contact whose normal is close to horizontal)
# and turns it into a crash even when the deck never tips past the ragdoll angle.
# The impulse itself is unreliable for a fresh contact, so the frame-to-frame speed
# loss is used instead: a wall removes momentum, while a bump merely redirects it.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var velocity := state.linear_velocity
	var old_horizontal := Vector3(_last_integrate_velocity.x, 0.0, _last_integrate_velocity.z)
	var new_horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var old_speed := old_horizontal.length()
	var new_speed := new_horizontal.length()
	# Only losing most of the speed means a wall. A curb or crosswalk redirects the
	# scooter (velocity vector changes a lot) but lets it keep rolling at speed.
	var speed_loss := old_speed - new_speed
	if (
		_has_last_integrate_velocity
		and old_speed >= crash_impact_speed
		and new_speed <= crash_stop_speed
		and speed_loss >= crash_impact_speed
		and not _has_pending_crash
		and _is_controller()
		and has_rider
	):
		var rider := get_rider()
		if rider != null and not rider.is_ragdolled:
			for i in state.get_contact_count():
				# Despite the name (and the outdated docs), this normal is world-space.
				var normal := state.get_contact_local_normal(i).normalized()
				# Ground and ramps push mostly upward; only near-vertical surfaces are walls.
				if absf(normal.y) > crash_max_normal_up:
					continue
				# Throw the rider the way the scooter was already travelling. If the hit
				# ate that velocity, reconstruct it from the wall normal instead.
				var throw_velocity := _last_integrate_velocity
				if throw_velocity.length() < speed_loss * 0.5:
					throw_velocity = -normal * speed_loss
				_pending_crash_velocity = throw_velocity
				_has_pending_crash = true
				break
	_last_integrate_velocity = velocity
	_has_last_integrate_velocity = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and has_rider and _is_controller():
		# Mouse steers: moving right turns right, matching the player's own look.
		_target_yaw -= event.relative.x * mouse_sensitivity
	super(event)


func interact(player_id: int) -> void:
	# A flipped scooter rights itself first; the next interaction rides it.
	if _is_flipped():
		_rpc_right_self.rpc()
		return
	super(player_id)


## A hit of any kind throws the rider off and ragdolls them, whatever the incoming
## [param ragdoll] flag asked for. The scooter itself is unharmed. [param _attacker_id]
## is accepted so melee hits can pass the attacking player's id (unused here).
func get_hit(
	damage: float,
	force: Vector3 = Vector3.ZERO,
	interrupt: bool = true,
	ragdoll: bool = false,
	_attacker_id: int = 0,
) -> void:
	_rpc_get_hit.rpc(damage, force, interrupt)


# Broadcast so the knock-off runs on the controller peer, the only one that actually
# holds the rider attached (analogous to _rpc_right_self).
@rpc("any_peer", "call_local", "reliable")
func _rpc_get_hit(damage: float, force: Vector3, interrupt: bool) -> void:
	if not _is_controller():
		return
	_throw_rider(damage, force, interrupt)


# Detaches the rider and starts their ragdoll, thrown by [param force].
func _throw_rider(damage: float, force: Vector3, interrupt: bool) -> void:
	var player := get_rider()
	if player == null:
		return
	_stop_riding()
	player.get_hit(damage, force, interrupt, true)


func _apply_controls(delta: float) -> void:
	if _self_righting:
		_apply_self_right(delta)
		return
	if not has_rider:
		return
	# A dismount now takes a server round-trip, during which rider_id is still set.
	# Ignore a rider who has already been ragdolled (e.g. thrown off by a crash or a
	# hit) so controls and _crash() don't fire again while the server confirms.
	var rider := get_rider()
	if rider == null or rider.is_ragdolled:
		return
	_apply_grip()
	_apply_throttle()
	_apply_steering()
	_apply_balance(delta)

	if _is_grounded() and _tilt_angle() > deg_to_rad(ragdoll_tilt_degrees):
		_crash(linear_velocity)


# Runs on the controller peer. Sweeps the detector along this frame's motion so a fast
# pass cannot tunnel through a pedestrian, then applies a normal hit to each new target.
func _check_run_overs(delta: float) -> void:
	var rider := get_rider()
	if rider == null or rider.is_ragdolled:
		return
	var speed := _horizontal_speed()
	if speed < run_over_min_speed:
		return

	_sync_detector_exception(rider)
	_runner_detector.target_position = (
		_runner_detector.global_basis.inverse() * (linear_velocity * delta)
	)
	_runner_detector.force_shapecast_update()

	var now := Time.get_ticks_msec()
	var cooldown_ms := int(run_over_cooldown * 1000.0)
	for i in _runner_detector.get_collision_count():
		var target := _runner_detector.get_collider(i) as Humanoid
		if target == null or target == rider or target.is_ragdolled:
			continue
		var target_id := target.get_instance_id()
		var last_hit: int = _recent_run_overs.get(target_id, -cooldown_ms)
		if now - last_hit < cooldown_ms:
			continue
		_recent_run_overs[target_id] = now
		_run_over(target, rider, speed)

	_prune_run_overs(now, cooldown_ms)


# Drives an actor down with the same damage, ragdoll and guilt effects as a melee hit.
func _run_over(target: Humanoid, rider: Player, speed: float) -> void:
	var damage := minf(speed * run_over_damage_per_speed, run_over_max_damage)
	var direction := Vector3(linear_velocity.x, 0.0, linear_velocity.z).normalized()
	if direction.is_zero_approx():
		direction = _forward()
	var force := direction * (speed * run_over_force_scale) + Vector3.UP * run_over_lift
	target.get_hit(damage, force, true, true, rider.player_id)
	_register_run_over_guilt(target, rider.player_id, damage)
	if run_over_sfx:
		Audio.play_sfx_3d(run_over_sfx, target.global_position, 0.0, 25.0, true)


# Mirrors melee assault guilt, but skips police (they turn a hit into bounty instead).
func _register_run_over_guilt(target: Humanoid, attacker_id: int, damage: float) -> void:
	if attacker_id <= 0 or not target.has_method("get_crime_label"):
		return
	if target.is_in_group("police"):
		return
	var label := "Ran over %s" % target.get_crime_label()
	var amount := maxi(25, roundi(damage * 4.0))
	CrimeManager.add_guilt(attacker_id, label, 90, amount)


# Keeps the rider out of the sweep. The rider's body has several shapes and would
# otherwise fill the cast results, hiding the pedestrian actually in front.
func _sync_detector_exception(rider: Player) -> void:
	if is_instance_valid(_detector_rider) and rider == _detector_rider:
		return
	if is_instance_valid(_detector_rider):
		_runner_detector.remove_exception(_detector_rider)
	_detector_rider = rider
	if _detector_rider != null:
		_runner_detector.add_exception(_detector_rider)


# Drops cooldown entries for actors the scooter can hit again.
func _prune_run_overs(now: int, cooldown_ms: int) -> void:
	if _recent_run_overs.size() < 32:
		return
	for target_id: int in _recent_run_overs.keys():
		if now - _recent_run_overs[target_id] >= cooldown_ms:
			_recent_run_overs.erase(target_id)


func _horizontal_speed() -> float:
	return Vector3(linear_velocity.x, 0.0, linear_velocity.z).length()


# Cancels the sideways part of the velocity while grounded, so the scooter tracks
# its heading instead of sliding the way a rigid body with no wheels would.
func _apply_grip() -> void:
	if not _is_grounded():
		return
	var lateral := _forward().cross(Vector3.UP)
	apply_central_force(-lateral * linear_velocity.dot(lateral) * lateral_grip)


func _apply_throttle() -> void:
	var throttle := Input.get_axis("move_down", "move_forward")
	if is_zero_approx(throttle):
		return
	var forward := _forward()
	if throttle > 0.0 and linear_velocity.dot(forward) >= max_speed:
		return
	apply_central_force(forward * engine_force * throttle)


func _apply_steering() -> void:
	var forward := _forward()
	var error := wrapf(_target_yaw - atan2(-forward.x, -forward.z), -PI, PI)
	apply_torque(Vector3.UP * (error * steer_strength - angular_velocity.y * steer_damping))


func _apply_balance(delta: float) -> void:
	var up := global_basis.y
	# Bleed off roll/pitch velocity. A blend stays stable no matter how high
	# balance_damping goes. Rotation about `up` is yaw, which steering owns.
	var roll_pitch := angular_velocity - up * angular_velocity.dot(up)
	angular_velocity -= roll_pitch * clampf(balance_damping * delta, 0.0, 1.0)
	# Right the deck (`up x world_up` tips it back upright) and add the A/D lean.
	var lean := Input.get_axis("move_left", "move_right")
	apply_torque(up.cross(Vector3.UP) * balance_strength - global_basis.z * lean * lean_torque)


# Swings the deck back upright along the shortest arc, so it recovers from fully
# upside down too (where `up x world_up` collapses to zero).
func _apply_self_right(delta: float) -> void:
	_self_right_time += delta
	var align := Quaternion(global_basis.y, Vector3.UP)
	var angle := align.get_angle()
	if angle < 0.02 or _self_right_time > right_self_duration:
		_self_righting = false
		return
	apply_torque(align.get_axis() * angle * right_self_torque - angular_velocity * right_self_damping)


# The heading flattened onto the ground plane, used for thrust, grip and steering.
func _forward() -> Vector3:
	var forward := -global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Vector3.FORWARD
	return forward.normalized()


func _is_flipped() -> bool:
	return _tilt_angle() > deg_to_rad(flipped_tilt_degrees)


func _is_grounded() -> bool:
	return get_contact_count() > 0


func _tilt_angle() -> float:
	return acos(clampf(global_basis.y.dot(Vector3.UP), -1.0, 1.0))


func _crash(throw_velocity: Vector3) -> void:
	if _crash_cooldown > 0.0:
		return
	var rider := get_rider()
	if rider == null or rider.is_ragdolled:
		return
	_crash_cooldown = 0.5
	_throw_rider(0.0, throw_velocity * crash_force_scale, true)


# Any peer may ask for the hop; only the controller applies it.
@rpc("any_peer", "call_local", "reliable")
func _rpc_right_self() -> void:
	if not _is_controller():
		return
	_self_righting = true
	_self_right_time = 0.0
	apply_central_impulse(Vector3.UP * flip_hop_impulse)
