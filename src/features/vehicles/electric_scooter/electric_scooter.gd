class_name ElectricScooter
extends Vehicle
## A self-balancing electric scooter. The rider steers by moving the mouse, keeps
## their balance with A/D (helped along by a constant small self-righting torque)
## and ragdolls if they let it tip too far while on the ground. A flipped scooter
## can be righted by interacting with it.

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

var _target_yaw := 0.0
var _self_righting := false
var _self_right_time := 0.0


func _ready() -> void:
	super()
	# Needed for the ground check in _is_grounded.
	contact_monitor = true
	max_contacts_reported = 8
	_target_yaw = global_rotation.y


func _physics_process(delta: float) -> void:
	if _is_controller():
		_apply_controls(delta)
	super(delta)


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


func _apply_controls(delta: float) -> void:
	if _self_righting:
		_apply_self_right(delta)
		return
	if not has_rider:
		return
	_apply_grip()
	_apply_throttle()
	_apply_steering()
	_apply_balance(delta)

	if _is_grounded() and _tilt_angle() > deg_to_rad(ragdoll_tilt_degrees):
		_crash()


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


func _crash() -> void:
	var player := get_rider()
	if player == null:
		return
	var throw := linear_velocity * crash_force_scale
	_stop_riding()
	player.get_hit(0.0, throw, true, true)


# Any peer may ask for the hop; only the controller applies it.
@rpc("any_peer", "call_local", "reliable")
func _rpc_right_self() -> void:
	if not _is_controller():
		return
	_self_righting = true
	_self_right_time = 0.0
	apply_central_impulse(Vector3.UP * flip_hop_impulse)
