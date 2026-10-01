class_name ActorRagdoll
extends Node
## Freezes the actor, starts a physics ragdoll, then blends the simulation influence
## back to 0 so the body eases from the fallen pose into the standing idle.
##
## The authority (players on their own peer, NPCs on the server) owns the actor's
## position: while flopped it tracks the ragdoll's root bone and replicates that. Other
## peers run the same flop for the visuals and pull their ragdoll's root toward the
## replicated position. Every peer also eases its origin along with the root bone, so the
## flop ends with the origin already on the body and the rise has no position to jump to.
##
## Shared by players and NPCs. The local player's camera (when set) follows the head
## bone while down.

## Physics layer the ragdoll bones use while simulated (project.godot layer 8,
## "ragdoll"). Their own layer, so a flopped actor is never detectable as a player.
const RAGDOLL_LAYER := 8
## World layers the bones collide with while flopped: environment and road.
const WORLD_LAYER := 1
const ROAD_LAYER := 7

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
## Largest distance the origin may be eased toward the root bone in one physics frame.
## Guards the origin against a physics spike (a fling) without needing to snap.
@export var max_origin_step := 1.0
## Spring pulling a non-authority ragdoll's root toward the replicated position, in
## metres of pull per metre of error per second squared (1/s^2). Higher converges
## faster but fights the flop harder.
@export var ragdoll_sync_stiffness := 12.0
## Largest corrective impulse a single frame may apply to that root, so a divergence
## spike cannot fling the body.
@export var ragdoll_max_sync_impulse := 4.0

## Marks whether the actor is ragdolled, blocks actions etc.
var is_ragdolled := false
## True during the short rise-back-up phase (physical skeleton influence being blended to 0).
var _rising := false
## Seconds spent in the current phase (the flop, then the rise).
var _state_time := 0.0
## Latest root bone world position, read in the pose phase and used by the physics-phase
## servo so a peer whose rendering lags its physics still converges correctly.
var _root_pos := Vector3.ZERO
## The local player's camera local transform before the flop moved it, restored on rise.
var _camera_rest_position := Vector3.ZERO
var _camera_rest_rotation := Vector3.ZERO

var _owner: Humanoid:
	get:
		return owner as Humanoid


## Freezes the actor and starts the physics ragdoll, applying [force] as the throw.
## Runs on every peer via the shared _rpc_get_hit so all clients see the same flop.
func start(force: Vector3) -> void:
	var h := _owner
	is_ragdolled = true
	_rising = false
	_state_time = 0.0
	_root_pos = h.global_position
	_store_camera_rest()
	h.velocity = Vector3.ZERO
	h._on_ragdoll_state_changed(true)
	if not h.is_local:
		# Start the local flop from the replicated transform so both simulations begin
		# from the same state instead of drifting apart from frame one.
		h.global_position = h.network_position
		h.global_rotation = h.network_rotation
	var rp := h.get_node_or_null("%RunParticles")
	if rp is GPUParticles3D:
		rp.emitting = false
	if is_instance_valid(h.animator):
		h.animator.cancel_action(0.0)
	if is_instance_valid(h.movement_collision):
		h.movement_collision.disabled = true
	if is_instance_valid(h.physical_bones):
		set_bone_collision(true)
		h.physical_bones.influence = 1.0
		if not h.physical_bones.modification_processed.is_connected(_on_pose_ready):
			h.physical_bones.modification_processed.connect(_on_pose_ready)
		# Stop first: a re-hit arrives while the simulator is still running. Stopping
		# clears that state, and starting again samples the pose the bones are actually in
		# now (physical_bones_start_simulation refreshes its cache before it begins), so
		# the fresh throw takes effect instead of being ignored.
		h.physical_bones.physical_bones_stop_simulation()
		h.physical_bones.physical_bones_start_simulation()
		for bone: Node in h.physical_bones.get_children():
			if bone is PhysicalBone3D:
				bone.apply_central_impulse(force * _ragdoll_impulse_scale_for(bone.bone_name))


## Advances the ragdoll timeline one physics frame. Called by [Humanoid] while ragdolled.
## Deliberately free of bone reads: a backgrounded server may render (and emit the
## modifier signal) far slower than it ticks physics, so timing must follow physics time
## rather than the pose-read cadence.
func tick(delta: float) -> void:
	_state_time += delta
	if _rising:
		var t := _rise_progress()
		if is_instance_valid(_owner.physical_bones):
			_owner.physical_bones.influence = 1.0 - t
		if t >= 1.0:
			_finish_rise()
		return
	if _state_time >= ragdoll_duration:
		_begin_rise()
		return
	if not _owner.is_local:
		_servo_root_to_sync(_root_pos, delta)


## Physical bone modifier callback, run once the final physics pose for the frame has
## been written. Reads the rig, drives the origin and the local camera. Every peer eases
## its origin along with the root bone (not just the authority) so the flop ends with the
## origin already on the body and the rise has no position to jump to.
func _on_pose_ready() -> void:
	if not is_ragdolled:
		return
	var h := _owner
	if not _rising:
		_root_pos = _bone_position("Root")
		_follow_root_bone(_root_pos)
	if h.is_local and is_instance_valid(h.camera):
		h.camera.global_position = _bone_position("Head_2")


## Ends the flop and starts the rise. The origin already sits on the body (it has tracked
## the root bone all flop), so the influence blend below brings the body up in place with
## no position to jump to. The animation is cancelled here (not at the end of the rise) so
## the blend always lands on the standing idle pose and the body is seen to get up.
func _begin_rise() -> void:
	var h := _owner
	h.velocity = Vector3.ZERO
	if is_instance_valid(h.animator):
		h.animator.cancel_action(0.1)
	if is_instance_valid(h.physical_bones):
		h.physical_bones.influence = 1.0
	_rising = true
	_state_time = 0.0


## Eased 0..1 progress of the current rise.
func _rise_progress() -> float:
	if ragdoll_rise_duration <= 0.0:
		return 1.0
	var t := clampf(_state_time / ragdoll_rise_duration, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Stops the simulation once the rise blend has reached the idle pose and hands the
## actor back control.
func _finish_rise() -> void:
	var h := _owner
	if is_instance_valid(h.physical_bones):
		# influence is already 0 here (rise complete); keep it there so stopping the
		# simulator cannot flash the last physics pose for a frame.
		h.physical_bones.influence = 0.0
		h.physical_bones.physical_bones_stop_simulation()
		set_bone_collision(false)
	if is_instance_valid(h.movement_collision):
		h.movement_collision.disabled = false
	h.velocity = Vector3.ZERO
	_rising = false
	is_ragdolled = false
	h._on_ragdoll_state_changed(false)
	if h.is_local and is_instance_valid(h.camera):
		_restore_camera()


## Eases the origin onto the ragdoll's root bone (X/Z only, keeping the standing height).
## Rejects non-finite reads and clamps one frame's displacement so a physics spike cannot
## fling the origin across the map. Only the authority owns the replicated transform, so
## remote peers move their own body without writing back to network_position.
func _follow_root_bone(bone_position: Vector3) -> void:
	var h := _owner
	if not bone_position.is_finite():
		return
	var offset := Vector3(
		bone_position.x - h.global_position.x, 0.0, bone_position.z - h.global_position.z
	)
	if offset.length() > max_origin_step:
		offset = offset.normalized() * max_origin_step
	h.global_position += offset
	if h.is_local:
		h.network_position = h.global_position
		h.network_rotation = h.global_rotation


## Non-authority: pulls the ragdoll's root bone horizontally toward the replicated
## position so the local flop settles where the authority's did. A spring impulse (rather
## than a velocity override) keeps the throw's momentum while removing the drift.
func _servo_root_to_sync(root_pos: Vector3, delta: float) -> void:
	var h := _owner
	if not h.network_position.is_finite():
		return
	var root := _find_physical_bone("Root")
	if root == null:
		return
	var error := Vector3(h.network_position.x - root_pos.x, 0.0, h.network_position.z - root_pos.z)
	var impulse := error * ragdoll_sync_stiffness * root.mass * delta
	root.apply_central_impulse(impulse.limit_length(ragdoll_max_sync_impulse))


## Remembers the camera's authored local transform so the flop can restore it.
func _store_camera_rest() -> void:
	var h := _owner
	if not is_instance_valid(h.camera):
		return
	_camera_rest_position = h.camera.position
	_camera_rest_rotation = h.camera.rotation


## Eases the camera back from the head bone to its standing transform.
func _restore_camera() -> void:
	var h := _owner
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(h.camera, "position", _camera_rest_position, 0.1)
	tw.tween_property(h.camera, "rotation", _camera_rest_rotation, 0.1)


## World-space position of a named rig bone, used to track the ragdoll's head/root.
func _bone_position(bone_name: StringName) -> Vector3:
	var h := _owner
	if not is_instance_valid(h.skeleton):
		return h.global_position
	var bone_idx := h.skeleton.find_bone(bone_name)
	if bone_idx == -1:
		return h.global_position
	return h.skeleton.to_global(h.skeleton.get_bone_global_pose(bone_idx).origin)


## The simulated physical bone body with the given name, if one exists.
func _find_physical_bone(bone_name: StringName) -> PhysicalBone3D:
	if not is_instance_valid(_owner.physical_bones):
		return null
	for bone: Node in _owner.physical_bones.get_children():
		if bone is PhysicalBone3D:
			if bone.bone_name == bone_name:
				return bone
	return null


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
## block anyone, while an active ragdoll collides with the world. The layers are
## assigned explicitly (not bit-set) so the result never depends on authored values.
func set_bone_collision(active: bool) -> void:
	if not is_instance_valid(_owner.physical_bones):
		return

	for bone: Node in _owner.physical_bones.get_children():
		if bone is PhysicalBone3D:
			bone.collision_layer = 0
			bone.collision_mask = 0
			if active:
				bone.set_collision_layer_value(RAGDOLL_LAYER, true)
				bone.set_collision_mask_value(WORLD_LAYER, true)
				bone.set_collision_mask_value(ROAD_LAYER, true)
