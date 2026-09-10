class_name PlayerCamera
extends Camera3D
## Damage feedback for the local player's camera: a short, damage-scaled "kick" that
## rotates the view up, then springs smoothly back to the authored base rotation.
## Implemented as a stable damped spring driven by an angular-velocity impulse, so
## light hits (punches) are still felt and heavy hits kick harder without oscillating.

@export_group("Damage Kick")
## Angular impulse (radians/second) applied per point of damage.
@export var impulse_per_damage := 0.36
## Minimum angular impulse (radians/second) so even light hits register.
@export var min_impulse := 1.8
## Maximum kick angle (radians) on top of the base rotation.
@export var max_pitch := 0.35
## Spring frequency in Hz. Higher snaps back faster.
@export var spring_frequency := 2.5
## Damping ratio. 1.0 is critically damped (no overshoot).
@export var spring_damping := 1.0

var _pitch := 0.0
var _pitch_velocity := 0.0
var _base_rotation := Vector3.ZERO


func _ready() -> void:
	_base_rotation = rotation


## Kicks the camera up, scaled by [param damage]. Call on the local camera when hit.
func add_damage_impact(damage: float) -> void:
	_pitch_velocity += min_impulse + damage * impulse_per_damage


func _process(delta: float) -> void:
	if absf(_pitch) < 0.0001 and absf(_pitch_velocity) < 0.0001:
		if _pitch != 0.0 or _pitch_velocity != 0.0:
			_pitch = 0.0
			_pitch_velocity = 0.0
			rotation = _base_rotation
		return

	# Stable implicit damped spring toward zero (target angle).
	var omega := TAU * spring_frequency
	var f := 1.0 + 2.0 * delta * spring_damping * omega
	var oo := omega * omega
	var hoo := delta * oo
	var hhoo := delta * hoo
	var det_inv := 1.0 / (f + hhoo)
	var new_pitch := (_pitch * f + _pitch_velocity * delta) * det_inv
	var new_velocity := (_pitch_velocity - _pitch * hoo) * det_inv
	_pitch = clampf(new_pitch, -max_pitch, max_pitch)
	_pitch_velocity = new_velocity

	# Negative X pitch looks up.
	rotation = _base_rotation + Vector3(-_pitch, 0.0, 0.0)
