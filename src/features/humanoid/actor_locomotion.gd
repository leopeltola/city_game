class_name ActorLocomotion
extends Node
## Moves the owner CharacterBody3D on the ground plane: applies gravity, jump, walk
## vs run speeds and acceleration, then move_and_slide. The owner feeds a desired
## world-space direction and a run request (input for players, AI for NPCs); whether
## running is actually allowed is decided by the owner via can_sprint() (stamina for
## players, always for NPCs).

@export var walk_speed := 3.0
@export var sprint_speed := 5.5
@export var jump_velocity := 6.0
@export var jump_cut_multiplier := 0.5
@export var gravity := 15.0

## World-space movement direction (normalized, or zero to stop). Written by the owner.
var desired_direction := Vector3.ZERO
## Whether the owner is trying to run this frame.
var run_requested := false
## Whether the system is enabled
var disabled := false


var _owner: Humanoid:
	get:
		return owner as Humanoid


## Applies gravity, horizontal acceleration and move_and_slide for the current
## desired direction. Called from the owner's physics process while on foot.
func step(delta: float) -> void:
	if disabled:
		return
	
	var h := _owner
	if not h.is_on_floor():
		h.velocity.y -= gravity * delta

	h.is_sprinting = run_requested and desired_direction != Vector3.ZERO and h.can_sprint()
	var active_speed := (sprint_speed if h.is_sprinting else walk_speed) * h.move_speed_multiplier * h.status.move_speed_multiplier()
	var target_vel := desired_direction * active_speed
	var accel := 10.0 if desired_direction != Vector3.ZERO else 8.0
	h.velocity.x = move_toward(h.velocity.x, target_vel.x, accel * delta * active_speed)
	h.velocity.z = move_toward(h.velocity.z, target_vel.z, accel * delta * active_speed)
	h.move_and_slide()


## Applies a jump impulse if the owner is on the floor. Returns true when it jumped.
func do_jump() -> bool:
	if not _owner.is_on_floor():
		return false
	_owner.velocity.y = jump_velocity
	return true


## Cuts the upward velocity when the jump key is released early.
func cut_jump() -> void:
	if _owner.velocity.y > 0.0:
		_owner.velocity.y *= jump_cut_multiplier
