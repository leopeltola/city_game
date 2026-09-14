class_name ActorRagdoll
extends Node
## Freezes the actor and starts a physics ragdoll, applies the throw impulse, tracks
## the origin on the root bone while flopped, then eases the simulation influence
## back to 0 so the body blends from the fallen pose to the standing idle.
##
## Shared by players and NPCs. The local player's camera (when set) follows the head
## bone while down.

@export_group("Ragdoll")
## How long a ragdolled victim stays flopped before standing back up
@export var ragdoll_duration := 1.5
## How long the physics -> idle blend takes while standing back up
@export var ragdoll_rise_duration := 0.3
## Multiplier on the incoming knockback force applied to the ragdoll's root bone
@export var ragdoll_impulse_scale := 1.0
## Multiplier on the root impulse applied to the head so it snaps back too
@export var ragdoll_head_impulse_scale := 0.6
## Multiplier on the root impulse applied to the hands
@export var ragdoll_limb_impulse_scale := 0.25

## Marks whether the actor is ragdolled, blocks actions etc.
var is_ragdolled := false
## True during the short rise-back-up phase (physical skeleton influence being blended to 0).
var _rising := false
var _rise_time := 0.0 ## rise counter
var _ragdoll_timer: SceneTreeTimer = null


var _owner: Humanoid:
	get:
		return owner as Humanoid


func is_rising() -> bool:
	return _rising


## Freezes the actor and starts the physics ragdoll, applying [force] as the throw.
## Runs on every peer via the shared _rpc_get_hit so all clients see the same flop.
func start(force: Vector3) -> void:
	var h := _owner
	is_ragdolled = true
	h.velocity = Vector3.ZERO
	var rp := h.get_node_or_null("%RunParticles")
	if rp is GPUParticles3D:
		rp.emitting = false
	if is_instance_valid(h.animator):
		h.animator.cancel_action(0.0)
	if is_instance_valid(h.movement_collision):
		h.movement_collision.disabled = true
	if is_instance_valid(h.physical_bones):
		_set_ragdoll_bone_collision(true)
		h.physical_bones.physical_bones_start_simulation()
		for bone: Node in h.physical_bones.get_children():
			if bone is PhysicalBone3D:
				bone.apply_central_impulse(force * _ragdoll_impulse_scale_for(bone.bone_name))
	_ragdoll_timer = get_tree().create_timer(ragdoll_duration)
	_ragdoll_timer.timeout.connect(_on_ragdoll_timeout)


## While ragdolled the origin follows the root bone across the floor (Y stays at the
## standing height, so the stand-up ends at the right capsule height). Reads are done
## here in the physics phase, AFTER the deferred modifier pass has written the final
## physics pose - reading in the idle phase would return the AnimationPlayer's pose.
func process_ragdoll(_delta: float) -> void:
	var h := _owner
	var root_pos := await _bone_global_position("Root")
	h.global_position.x = root_pos.x
	h.global_position.z = root_pos.z
	h.network_position = h.global_position
	h.network_rotation = h.global_rotation
	if h.is_local and is_instance_valid(h.camera):
		h.camera.global_position = await _bone_global_position("Head_2")


## Ends the flop and starts the rise: keeps the simulation running and eases its
## influence to 0, so the visible pose blends from the fallen body to the standing
## idle instead of snapping. No bone poses are read here (they are unreliable in the
## idle phase); the origin is already at the body's resting spot from process_ragdoll.
func _on_ragdoll_timeout() -> void:
	if not is_inside_tree() or not is_ragdolled or _rising:
		return
	_owner.velocity = Vector3.ZERO
	_rising = true
	_rise_time = 0.0


## Tweens the physics simulator's influence 1 -> 0 so the engine blends the rig from
## the fallen physics pose toward the standing idle animation.
func process_rise(delta: float) -> void:
	_rise_time += delta
	var t := clampf(_rise_time / ragdoll_rise_duration, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	if is_instance_valid(_owner.physical_bones):
		_owner.physical_bones.influence = 1.0 - t
	if t >= 1.0:
		_finish_rise()


## Physics-phase handler while rising: keeps the origin glued to the (blended) root
## bone and the camera on the (blended) head as the body straightens up.
func process_rise_physics(_delta: float) -> void:
	var h := _owner
	var root_pos := await _bone_global_position("Root")
	h.global_position.x = root_pos.x
	h.global_position.z = root_pos.z
	h.network_position = h.global_position
	h.network_rotation = h.global_rotation
	if h.is_local and is_instance_valid(h.camera):
		h.camera.global_position = await _bone_global_position("Head_2")


## Stops the simulation once the rise blend has reached the idle pose and hands the
## actor back control.
func _finish_rise() -> void:
	var h := _owner
	if is_instance_valid(h.physical_bones):
		h.physical_bones.influence = 1.0
		h.physical_bones.physical_bones_stop_simulation()
		_set_ragdoll_bone_collision(false)
	if is_instance_valid(h.movement_collision):
		h.movement_collision.disabled = false
	h.velocity = Vector3.ZERO
	_rising = false
	is_ragdolled = false
	if is_instance_valid(h.animator):
		h.animator.cancel_action(0.1)
	if h.is_local and is_instance_valid(h.camera):
		# Restore the camera's authored local transform under SightPivot.
		await get_tree().process_frame
		await get_tree().process_frame
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(h.camera, "position", Vector3(0.0, 0.15345, -0.060455), 0.1)
		tw.tween_property(h.camera, "rotation", Vector3.ZERO, 0.1)


## World-space position of a named rig bone, used to track the ragdoll's head/root.
func _bone_global_position(bone_name: StringName) -> Vector3:
	var h := _owner
	if not is_instance_valid(h.skeleton):
		return h.global_position
	var bone_idx := h.skeleton.find_bone(bone_name)
	if bone_idx == -1:
		return h.global_position
	await h.physical_bones.modification_processed
	return h.skeleton.to_global(h.skeleton.get_bone_global_pose(bone_idx).origin)


## Per-bone impulse scale: the root takes the full knockback, the head a good chunk
## so it snaps back, limbs a lighter follow-through.
func _ragdoll_impulse_scale_for(bone_name: StringName) -> float:
	match bone_name:
		"Root":
			return ragdoll_impulse_scale
		"Head_2":
			return ragdoll_impulse_scale * ragdoll_head_impulse_scale
		_:
			return ragdoll_impulse_scale * ragdoll_limb_impulse_scale


## Toggles the physical bone bodies' collision so the idle kinematic bodies never
## block anyone, while an active ragdoll collides with the world.
func _set_ragdoll_bone_collision(active: bool) -> void:
	var h := _owner
	if not is_instance_valid(h.physical_bones):
		return
	for bone: Node in h.physical_bones.get_children():
		if bone is PhysicalBone3D:
			bone.collision_layer = 2 if active else 0
			bone.collision_mask = 1 if active else 0