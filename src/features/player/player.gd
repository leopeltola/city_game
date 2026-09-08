class_name Player
extends CharacterBody3D

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

var _override_anim := ""

## Multiplier applied to mouse look sensitivity. Lower values simulate drag/resistance.
var look_drag_multiplier := 1.0
## Multiplier applied to movement speed.
var move_speed_multiplier := 1.0
var is_blocking := false
var is_sprinting := false

@export var walk_speed: float = 3.0
@export var sprint_speed: float = 5.5
@export var jump_velocity: float = 6
@export var mouse_sensitivity: float = 0.003
@export var gravity: float = 15

@export_group("Stamina")
@export var max_stamina: float = 100.0
## Stamina drained per second while sprinting (~4.5 seconds of continuous sprinting).
@export var stamina_drain_rate: float = 22.0
## Stamina recovered per second when not sprinting (~2.5 seconds to full recovery).
@export var stamina_regen_rate: float = 40.0

var stamina: float = 100.0

@onready var sight_pivot: Node3D = %SightPivot
@onready var anim_player: AnimationPlayer = $Visual/guy/AnimationPlayer
@onready var hittable_area: Area3D = %HittableArea

## Authoritative world transform written by the local player and replicated via
## MultiplayerSynchronizer. Remote peers interpolate their body toward these.
var network_position: Vector3
var network_rotation: Vector3

## How quickly remote players catch up to the latest synced position.
@export var network_interp_speed := 12.0
var _network_interp_ready := false


func _ready() -> void:
	assert(player_id)
	assert(inventory)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	PlayerManager.register_player_node(self)

	stamina = max_stamina
	anim_player.animation_finished.connect(_on_animation_finished)

	network_position = global_position
	network_rotation = global_rotation

	if is_local:
		%Camera3D.make_current()
		%ItemInventoryUI.show()
		if HUD.instance:
			HUD.instance.set_stamina(1.0)
		$Visual/guy/Armature/Skeleton3D/Head.hide()
		$Visual/guy/Armature/Skeleton3D/Body.hide()


func _process(_delta: float) -> void:
	if not _override_anim:
		var idle_anim := inventory.get_idle_animation_override()
		anim_player.play(idle_anim if not idle_anim.is_empty() else "idle")

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

	if not is_on_floor():
		velocity.y -= gravity * delta

	_jumping(delta)
	_walking(delta)

	move_and_slide()

	network_position = global_position
	network_rotation = global_rotation


func _unhandled_input(event: InputEvent) -> void:
	if not is_local or (HUD.instance and HUD.instance.is_blocking_input()):
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

## Emitted when an override animation naturally finishes or is explicitly canceled.
signal override_anim_finished


## Returns equipped item if any exists. Null otherwise
func get_equipped_item() -> ItemEquip:
	return inventory._equipped_node


## Plays an animation, yielding until natural completion or cancellation.
func play_override_animation(anim_name: String, blend_time: float = 0.0) -> void:
	_override_anim = anim_name
	anim_player.play(anim_name, blend_time)
	await override_anim_finished


## Cancels the current override animation and safely resumes execution for yielded scripts.
func cancel_override_animation(blend_time: float = 0.0) -> void:
	if _override_anim == "":
		return
	_override_anim = ""
	anim_player.play("idle", blend_time)
	override_anim_finished.emit()


## Triggers a quick block recovery network call.
func trigger_block_success() -> void:
	_rpc_trigger_block_success.rpc()


func _jumping(_delta: float) -> void:
	if Input.is_action_just_pressed("jump") and is_on_floor():
		if HUD.instance and HUD.instance.is_blocking_input():
			return
		velocity.y = jump_velocity


func _walking(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_down")
	if HUD.instance and HUD.instance.is_blocking_input():
		input_dir = Vector2.ZERO
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var sprint_held := Input.is_physical_key_pressed(KEY_SHIFT) and Input.is_action_pressed("sprint")
	var wants_to_sprint := sprint_held and direction != Vector3.ZERO
	is_sprinting = wants_to_sprint and stamina > 0.0

	if wants_to_sprint:
		stamina = maxf(stamina - stamina_drain_rate * delta, 0.0)
	else:
		stamina = minf(stamina + stamina_regen_rate * delta, max_stamina)

	if HUD.instance:
		HUD.instance.set_stamina(stamina / max_stamina)

	%RunParticles.emitting = is_sprinting and is_on_floor()
	%Camera3D.fov = lerpf(%Camera3D.fov, 105, 0.1) if is_sprinting else lerpf(%Camera3D.fov, 75, 0.1)

	var active_speed := (sprint_speed if is_sprinting else walk_speed) * move_speed_multiplier
	var target_vel := direction * active_speed
	var accel := 10.0 if direction else 8.0
	velocity.x = move_toward(velocity.x, target_vel.x, accel * delta * active_speed)
	velocity.z = move_toward(velocity.z, target_vel.z, accel * delta * active_speed)


func _on_animation_finished(anim_name: String) -> void:
	if anim_name == _override_anim:
		_override_anim = ""
		override_anim_finished.emit()


@rpc("any_peer", "call_local", "reliable")
func _rpc_trigger_block_success() -> void:
	is_blocking = false
	cancel_override_animation(0.1)


## Applies damage and knockback force to the player.
func get_hit(_damage: float, force: Vector3) -> void:
	_rpc_get_hit.rpc(_damage, force)


@rpc("any_peer", "reliable")
func _rpc_get_hit(_damage: float, force: Vector3) -> void:
	velocity += force

	if is_local:
		_spawn_knocked_item()


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
