extends ItemEquip

## Emitted when a bottle shatters due to impact forces.
signal bottle_broken(bottle: Node3D)

## Spring stiffness for sway tilt recovery.
@export var sway_stiffness: float = 24.0
## Damping factor to prevent endless wobbling.
@export var sway_damping: float = 5.0
## Tilt sensitivity to crate linear acceleration (running/strafing).
@export var linear_sway: float = 0.2
## Tilt sensitivity to crate angular velocity (camera yaw/pitch).
@export var angular_sway: float = 0.12
## Maximum tilt angle in radians (~20 degrees).
@export var max_sway_angle: float = 0.35

## Maximum vertical float height in meters (~1:1 scale airtime).
@export var max_airtime: float = 0.05
## Downward gravity pulling floating bottles back onto the crate floor.
@export var bottle_gravity: float = 12.0
## Multiplier translating crate downward acceleration into bottle lift.
@export var airtime_lift: float = 1.6
## Velocity restitution when bottles hit the bottom of the crate.
@export var bounciness: float = 0.2
## Downward impact velocity required to shatter a bottle on landing.
@export var break_impact_velocity: float = 6.5
## Relative variation factor for bottle airtime responsiveness.
@export var airtime_stagger: float = 0.15

@onready var bottles: Array[Node3D] = [
	%wine_bottle1,
	%wine_bottle2,
	%wine_bottle3,
	%wine_bottle4,
	%wine_bottle5,
	%wine_bottle6,
]

var _last_pos: Vector3
var _last_vel: Vector3
var _last_basis: Basis

var _sway_angle: Vector2 = Vector2.ZERO
var _sway_vel: Vector2 = Vector2.ZERO

var _bottle_y: Dictionary = {}
var _bottle_vy: Dictionary = {}
var _bottle_stagger: Dictionary = {}

var _base_positions: Dictionary = {}
var _base_rotations: Dictionary = {}


func _ready() -> void:
	_last_pos = global_position
	_last_basis = global_basis

	var bottle_count: int = ItemManager.get_item_data(item_id, "bottles", 6)
	var to_erase := []
	for i in 6 - bottle_count:
		var b := bottles[i]
		bottles[i].queue_free()
		to_erase.append(b)
	for b in to_erase:
		bottles.erase(b)

	for bottle in bottles:
		if is_instance_valid(bottle):
			_base_positions[bottle] = bottle.position
			_base_rotations[bottle] = bottle.rotation
			_bottle_y[bottle] = 0.0
			_bottle_vy[bottle] = 0.0
			_bottle_stagger[bottle] = randf_range(1.0 - airtime_stagger, 1.0 + airtime_stagger)


func _process(delta: float) -> void:
	if delta <= 0.0:
		return

	var current_pos: Vector3 = global_position
	var current_basis: Basis = global_basis

	var vel: Vector3 = (current_pos - _last_pos) / delta
	var accel: Vector3 = (vel - _last_vel) / delta
	var delta_basis: Basis = _last_basis.inverse() * current_basis
	var ang_vel: Vector3 = delta_basis.get_euler() / delta

	_last_pos = current_pos
	_last_vel = vel
	_last_basis = current_basis

	var local_accel: Vector3 = current_basis.inverse() * accel

	_update_airtime(delta, local_accel.y, vel.y)
	_update_sway(delta, local_accel, ang_vel)
	_apply_transforms()


## Shatters a specific bottle and removes it from tracking.
func shatter_bottle(bottle: Node3D) -> void:
	if not is_instance_valid(bottle):
		return
	bottles.erase(bottle)
	_base_positions.erase(bottle)
	_base_rotations.erase(bottle)
	_bottle_y.erase(bottle)
	_bottle_vy.erase(bottle)
	_bottle_stagger.erase(bottle)
	bottle_broken.emit(bottle)
	bottle.queue_free()
	ItemManager.set_and_sync_item_data(item_id, "bottles", bottles.size())


## Applies an external physical hit (e.g. melee, projectile, explosion).
func apply_impulse(impulse: Vector3) -> void:
	var local_impulse: Vector3 = global_basis.inverse() * impulse
	_sway_vel += Vector2(-local_impulse.z, local_impulse.x) * linear_sway
	for bottle in bottles:
		var stagger: float = _bottle_stagger.get(bottle, 1.0)
		_bottle_vy[bottle] = _bottle_vy.get(bottle, 0.0) + local_impulse.y * stagger
	if impulse.length() >= break_impact_velocity and not bottles.is_empty():
		shatter_bottle(bottles.front())


func _update_airtime(delta: float, local_accel_y: float, world_vel_y: float) -> void:
	var lift_accel: float = minf(local_accel_y, 0.0) if world_vel_y < 0.0 else 0.0
	var to_shatter: Array[Node3D] = []

	for bottle in bottles:
		var stagger: float = _bottle_stagger.get(bottle, 1.0)
		var y: float = _bottle_y.get(bottle, 0.0)
		var vy: float = _bottle_vy.get(bottle, 0.0)
		var was_airborne: bool = y > 0.002

		vy -= (lift_accel * airtime_lift * stagger + bottle_gravity) * delta
		y += vy * delta

		if y > max_airtime:
			y = max_airtime
			vy = minf(vy, 0.0)
		elif y <= 0.0:
			y = 0.0
			var impact_speed: float = -vy
			if impact_speed >= 2 and is_multiplayer_authority():
				print(impact_speed)
			if was_airborne and (impact_speed * randf_range(0.5, 1.2) >= break_impact_velocity):
				to_shatter.append(bottle)
			vy = -vy * (bounciness * stagger)

		_bottle_y[bottle] = y
		_bottle_vy[bottle] = vy

	for bottle in to_shatter:
		shatter_bottle(bottle)


func _update_sway(delta: float, local_accel: Vector3, ang_vel: Vector3) -> void:
	var target_force: Vector2 = Vector2(
		-local_accel.z * linear_sway - ang_vel.x * angular_sway,
		local_accel.x * linear_sway + ang_vel.y * angular_sway,
	)

	var spring: Vector2 = -sway_stiffness * _sway_angle - sway_damping * _sway_vel + target_force
	_sway_vel += spring * delta
	_sway_angle += _sway_vel * delta
	_sway_angle = _sway_angle.clamp(
		Vector2(-max_sway_angle, -max_sway_angle),
		Vector2(max_sway_angle, max_sway_angle),
	)


func _apply_transforms() -> void:
	for bottle in bottles:
		if is_instance_valid(bottle):
			var base_pos: Vector3 = _base_positions.get(bottle, Vector3.ZERO)
			var base_rot: Vector3 = _base_rotations.get(bottle, Vector3.ZERO)
			var y: float = _bottle_y.get(bottle, 0.0)

			bottle.position = base_pos + Vector3(0.0, y, 0.0)
			bottle.rotation = Vector3(
				base_rot.x + _sway_angle.x,
				base_rot.y,
				base_rot.z + _sway_angle.y,
			)
