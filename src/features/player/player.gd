class_name Player
extends CharacterBody3D

@export var jump_sfx: AudioStream

@export var inventory: PlayerInventory = null
@export var player_id := 0:
	set(val):
		player_id = val
		if player_id == 0:
			return
		is_local = player_data.is_local()
var player_data: PlayerData:
	get:
		return PlayerManager.get_player_by_id(player_id)
var is_local: bool

## Multiplier applied to mouse look sensitivity. Lower values simulate drag/resistance.
var look_drag_multiplier := 1.0
## Multiplier applied to movement speed.
var move_speed_multiplier := 1.0
var is_blocking := false
var is_sprinting := false

@export var walk_speed: float = 3.0
@export var sprint_speed: float = 5.5
@export var jump_velocity: float = 6.0
@export var jump_cut_multiplier: float = 0.5
@export var mouse_sensitivity: float = 0.003
@export var gravity: float = 15

@export_group("Stamina")
@export var max_stamina: float = 100.0
## Stamina drained per second while sprinting (~4.5 seconds of continuous sprinting).
@export var stamina_drain_rate: float = 22.0
## Stamina recovered per second when not sprinting (~2.5 seconds to full recovery).
@export var stamina_regen_rate: float = 40.0

var stamina: float = 100.0

@export_group("Hit Reaction")
## Speed multiplier applied while the on-hit movement debuff is active.
@export var hit_slow_multiplier: float = 0.5
## Debuff duration = base + damage * per_damage, clamped to [base, max].
@export var hit_slow_base_duration: float = 0.5
@export var hit_slow_per_damage: float = 0.1
@export var hit_slow_max_duration: float = 3.0
## Rig clip played when staggered (by a blocked attack or an interrupting hit).
@export var stagger_animation: String = "stagger"
## Blend used to enter/leave the stagger clip.
@export var stagger_blend: float = 0.1
## Fallback lock duration when the stagger clip is not imported yet.
@export var stagger_fallback_duration: float = 0.8

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

const SLOW_EFFECT_ID := &"hit_slow"
const STAGGER_EFFECT_ID := &"stagger"

@onready var sight_pivot: Node3D = %SightPivot
@onready var hittable_area: Area3D = %HittableArea
@onready var hittable_area_col_shape: CollisionShape3D = %HittableAreaCollisionShape
@onready var animator: PlayerAnimator = %PlayerAnimator
@onready var status: PlayerStatus = %PlayerStatus
@onready var camera: PlayerCamera = %Camera3D
@onready var skeleton: Skeleton3D = $Visual/guy/Armature/Skeleton3D
@onready var physical_bones: PhysicalBoneSimulator3D = $Visual/guy/Armature/Skeleton3D/PhysicalBoneSimulator3D
@onready var movement_collision: CollisionShape3D = $CollisionShape3D

## Authoritative world transform written by the local player and replicated via
## MultiplayerSynchronizer. Remote peers interpolate their body toward these.
var network_position: Vector3
var network_rotation: Vector3

## How quickly remote players catch up to the latest synced position.
@export var network_interp_speed := 12.0
var _network_interp_ready := false

## Marks whether is ragdolled, blocks actions etc
var is_ragdolled := false
## True during the short rise-back-up phase (physical skeleton influence being blended to 0).
var _rising := false
var _rise_time := 0.0 ## rise counter
var _ragdoll_timer: SceneTreeTimer = null


func _ready() -> void:
	assert(player_id)
	assert(inventory)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	PlayerManager.register_player_node(self)

	stamina = max_stamina
	_set_ragdoll_bone_collision(false)

	network_position = global_position
	network_rotation = global_rotation

	if is_local:
		%Camera3D.make_current()
		%ItemInventoryUI.show()
		if HUD.instance:
			HUD.instance.set_stamina(1.0)
		$Visual/guy/Armature/Skeleton3D/Head.hide()
		$Visual/guy/Armature/Skeleton3D/Body.hide()


func _process(delta: float) -> void:
	if _rising:
		_process_rise(delta)
	if Input.is_action_just_pressed("show_player_names") and is_local:
		print("SightPivot.position: %s\nCamera.position: %s" % [sight_pivot.position, camera.position])
	if Input.is_action_pressed("show_player_names") and Net.is_client:
		%NameLabel3D.text = player_data.player_name
		%NameLabel3D.show()
		if is_local:
			%OwnNameLabel.text = player_data.player_name
			%OwnNameLabel.show()
	else:
		%NameLabel3D.hide()
		%OwnNameLabel.hide()


func _physics_process(delta: float) -> void:
	if not is_local:
		_interpolate_network_transform(delta)
		return
	
	hittable_area_col_shape.disabled = is_ragdolled # Can't be hit if ragdolled
	if is_ragdolled:
		if _rising:
			_process_rise_physics(delta)
		else:
			_process_ragdoll(delta)
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	_jumping(delta)
	_walking(delta)

	move_and_slide()

	network_position = global_position
	network_rotation = global_rotation


func _unhandled_input(event: InputEvent) -> void:
	if not is_local or is_ragdolled or (HUD.instance and HUD.instance.is_blocking_input()):
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var effective_sensitivity := mouse_sensitivity * look_drag_multiplier
		rotate_y(-event.relative.x * effective_sensitivity)
		sight_pivot.rotate_x(-event.relative.y * effective_sensitivity)
		sight_pivot.rotation.x = clamp(sight_pivot.rotation.x, deg_to_rad(-85), deg_to_rad(85))
	if event.is_action_pressed("free_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_released("free_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Consumes a fixed amount of stamina. Returns true if the cost was met.
func consume_stamina(amount: float) -> bool:
	if stamina < amount:
		if is_local and HUD.instance:
			HUD.instance.punch_stamina(Vector2(0.85, 1.15), 10.0)
		return false

	stamina = maxf(stamina - amount, 0.0)
	if is_local and HUD.instance:
		HUD.instance.set_stamina(stamina / max_stamina)
	return true


## Checks whether the player currently has at least the specified amount of stamina.
func has_stamina(amount: float) -> bool:
	return stamina >= amount


## Returns equipped item if any exists (including unarmed gear like fists). Null otherwise.
func get_equipped_item() -> ItemEquip:
	return inventory._equipped_node


## True while a status effect (e.g. stagger) locks combat and slot-switch input.
func is_action_locked() -> bool:
	return is_ragdolled or status.is_action_locked()


## Plays the stagger clip and locks combat / slot switching for its duration.
func enter_stagger() -> void:
	var effect := StatusEffect.new()
	effect.id = STAGGER_EFFECT_ID
	effect.duration = _stagger_duration()
	effect.locks_actions = true
	status.add(effect)

	if is_instance_valid(animator) and is_instance_valid(animator.anim_player) \
			and animator.anim_player.has_animation(stagger_animation):
		animator.play_action(stagger_animation, stagger_blend, stagger_blend)


## Length of the stagger clip if imported, else the configured fallback.
func _stagger_duration() -> float:
	if is_instance_valid(animator) and is_instance_valid(animator.anim_player):
		var clip := animator.anim_player.get_animation(stagger_animation)
		if clip != null:
			return clip.length
	return stagger_fallback_duration


## Triggers a quick block recovery network call.
func trigger_block_success() -> void:
	_rpc_trigger_block_success.rpc()


func _jumping(_delta: float) -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		if HUD.instance and HUD.instance.is_blocking_input():
			return
		velocity.y = jump_velocity
		_rpc_play_sfx.rpc("jump")
	elif Input.is_action_just_released("jump") and velocity.y > 0.0:
		velocity.y *= jump_cut_multiplier


func _walking(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_down")
	if HUD.instance and HUD.instance.is_blocking_input():
		input_dir = Vector2.ZERO
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var sprint_held := Input.is_physical_key_pressed(KEY_SHIFT) and Input.is_action_pressed("sprint")
	var wants_to_sprint := sprint_held and direction != Vector3.ZERO
	is_sprinting = wants_to_sprint and stamina > 0.0 and status.can_sprint()

	if wants_to_sprint:
		stamina = maxf(stamina - stamina_drain_rate * delta, 0.0)
	else:
		stamina = minf(stamina + stamina_regen_rate * delta, max_stamina)

	if HUD.instance:
		HUD.instance.set_stamina(stamina / max_stamina)

	%RunParticles.emitting = is_sprinting and is_on_floor()
	%Camera3D.fov = lerpf(%Camera3D.fov, 105, 0.1) if is_sprinting else lerpf(%Camera3D.fov, 75, 0.1)

	var active_speed := (sprint_speed if is_sprinting else walk_speed) * move_speed_multiplier * status.move_speed_multiplier()
	var target_vel := direction * active_speed
	var accel := 10.0 if direction else 8.0
	velocity.x = move_toward(velocity.x, target_vel.x, accel * delta * active_speed)
	velocity.z = move_toward(velocity.z, target_vel.z, accel * delta * active_speed)


@rpc("any_peer", "call_local", "reliable")
func _rpc_trigger_block_success() -> void:
	is_blocking = false
	animator.cancel_action(0.1)


## Applies damage and knockback to the player and resolves hit reactions.
## [param interrupt] is the attacking weapon's interrupts_target flag: when true and
## the player is mid-action, the hit staggers them.
## [param ragdoll] when true, the hit flops the player into a physics ragdoll
## (thrown by [param force]) instead of the regular stagger response.
func get_hit(damage: float, force: Vector3 = Vector3.ZERO, interrupt: bool = true, ragdoll: bool = false) -> void:
	_rpc_get_hit.rpc(damage, force, interrupt, ragdoll)


@rpc("any_peer", "call_local", "reliable")
func _rpc_get_hit(damage: float, force: Vector3, interrupt: bool, ragdoll: bool) -> void:
	if is_ragdolled:
		return
	velocity += force
	_apply_hit_slow(damage)

	if is_local:
		if randf() < Combat.item_drop_chance(damage):
			_spawn_knocked_item()
		if is_instance_valid(camera):
			camera.add_damage_impact(damage)
		# Put the camera away before the knock; camera_out replicates to every peer.
		if inventory.camera_out:
			inventory.camera_out = false

	if ragdoll:
		_start_ragdoll(force)
	elif interrupt and is_instance_valid(animator) and animator.is_action_playing():
		enter_stagger()


## Applies the temporary on-hit movement debuff; duration scales with damage.
func _apply_hit_slow(damage: float) -> void:
	var effect := StatusEffect.new()
	effect.id = SLOW_EFFECT_ID
	effect.duration = clampf(
		hit_slow_base_duration + damage * hit_slow_per_damage,
		hit_slow_base_duration,
		hit_slow_max_duration
	)
	effect.move_speed_multiplier = hit_slow_multiplier
	effect.can_sprint = false
	status.add(effect)


## Freezes the player and starts the physics ragdoll, applying [force] as the throw.
## Runs on every peer via _rpc_get_hit so all clients see the same flop.
func _start_ragdoll(force: Vector3) -> void:
	is_ragdolled = true
	velocity = Vector3.ZERO
	%RunParticles.emitting = false
	if is_instance_valid(animator):
		animator.cancel_action(0.0)
	if is_instance_valid(movement_collision):
		movement_collision.disabled = true
	if is_instance_valid(physical_bones):
		_set_ragdoll_bone_collision(true)
		physical_bones.physical_bones_start_simulation()
		for bone: Node in physical_bones.get_children():
			if bone is PhysicalBone3D:
				bone.apply_central_impulse(force * _ragdoll_impulse_scale_for(bone.bone_name))
	_ragdoll_timer = get_tree().create_timer(ragdoll_duration)
	_ragdoll_timer.timeout.connect(_on_ragdoll_timeout)


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


## While ragdolled the origin follows the root bone across the floor (Y stays at the
## standing height, so the stand-up ends at the right capsule height). Reads are done
## here in the physics phase, AFTER the deferred modifier pass has written the final
## physics pose - reading in the idle phase would return the AnimationPlayer's pose.
func _process_ragdoll(_delta: float) -> void:
	var root_pos := await _bone_global_position("Root")
	
	global_position.x = root_pos.x
	global_position.z = root_pos.z
	network_position = global_position
	network_rotation = global_rotation
	if is_local and is_instance_valid(camera):
		camera.global_position = await _bone_global_position("Head_2")


## Ends the flop and starts the rise: keeps the simulation running and eases its
## influence to 0, so the visible pose blends from the fallen body to the standing
## idle instead of snapping. No bone poses are read here (they are unreliable in the
## idle phase); the origin is already at the body's resting spot from _process_ragdoll.
func _on_ragdoll_timeout() -> void:
	if not is_inside_tree() or not is_ragdolled or _rising:
		return
	velocity = Vector3.ZERO
	_rising = true
	_rise_time = 0.0


## Tweens the physics simulator's influence 1 -> 0 so the engine blends the rig from
## the fallen physics pose toward the standing idle animation.
func _process_rise(delta: float) -> void:
	_rise_time += delta
	var t := clampf(_rise_time / ragdoll_rise_duration, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	if is_instance_valid(physical_bones):
		physical_bones.influence = 1.0 - t
	if t >= 1.0:
		_finish_rise()


## Physics-phase handler while rising: keeps the origin glued to the (blended) root
## bone and the camera on the (blended) head as the body straightens up.
func _process_rise_physics(_delta: float) -> void:
	var root_pos := await _bone_global_position("Root")
	global_position.x = root_pos.x
	global_position.z = root_pos.z
	network_position = global_position
	network_rotation = global_rotation
	if is_local and is_instance_valid(camera):
		camera.global_position = await _bone_global_position("Head_2")


## Stops the simulation once the rise blend has reached the idle pose and hands the
## player back control.
func _finish_rise() -> void:
	if is_instance_valid(physical_bones):
		physical_bones.influence = 1.0
		physical_bones.physical_bones_stop_simulation()
		_set_ragdoll_bone_collision(false)
	if is_instance_valid(movement_collision):
		movement_collision.disabled = false
	velocity = Vector3.ZERO
	_rising = false
	is_ragdolled = false
	if is_instance_valid(animator):
		animator.cancel_action(0.1)
	if is_local and is_instance_valid(camera):
		# Restore the camera's authored local transform under SightPivot.
		await get_tree().process_frame
		await get_tree().process_frame
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(camera, "position", Vector3(0.0, 0.15345, -0.060455), 0.1)
		tw.tween_property(camera, "rotation", Vector3.ZERO, 0.1)


## World-space position of a named rig bone, used to track the ragdoll's head/root.
func _bone_global_position(bone_name: StringName) -> Vector3:
	if not is_instance_valid(skeleton):
		return global_position
	var bone_idx := skeleton.find_bone(bone_name)
	if bone_idx == -1:
		return global_position
	await %PhysicalBoneSimulator3D.modification_processed
	return skeleton.to_global(skeleton.get_bone_global_pose(bone_idx).origin)


## Toggles the physical bone bodies' collision so the idle kinematic bodies never
## block the player (or anyone else), while an active ragdoll collides with the world.
func _set_ragdoll_bone_collision(active: bool) -> void:
	if not is_instance_valid(physical_bones):
		return
	for bone: Node in physical_bones.get_children():
		if bone is PhysicalBone3D:
			bone.collision_layer = 2 if active else 0
			bone.collision_mask = 1 if active else 0


@rpc("any_peer", "reliable", "call_local")
func _rpc_play_sfx(id: StringName) -> void:
	match id:
		"jump":
			Audio.play_sfx_3d(jump_sfx, global_position)


## Knocks a random inventory item out of the player: spawned 1m above them with a
## random upward/sideways launch force.
func _spawn_knocked_item() -> void:
	var dir := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	if dir.length_squared() < 0.01:
		dir = Vector3.FORWARD
	dir = dir.normalized()

	var force := dir * randf_range(3.0, 6.5) + Vector3.UP * randf_range(2.0, 4.0)
	inventory.drop_random_item(global_position + Vector3.UP, force)


## Smoothly moves a remote player's body toward the latest synced transform.
func _interpolate_network_transform(delta: float) -> void:
	if not _network_interp_ready:
		global_position = network_position
		global_rotation = network_rotation
		_network_interp_ready = true
		return

	var k := 1.0 - exp(-network_interp_speed * delta)
	global_position = global_position.lerp(network_position, k)
	global_basis = global_basis.slerp(Basis.from_euler(network_rotation), k)


func _to_string() -> String:
	return "Player: %s" % str(player_data)
