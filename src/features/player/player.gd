class_name Player
extends Humanoid
## The locally-controlled player character. Adds identity (player_id / PlayerData),
## mouse-look, the camera, stamina, HUD wiring and the full slot inventory on top of
## the shared Humanoid base.

@export var jump_sfx: AudioStream

@export var player_id := 0:
	set(val):
		player_id = val
		if player_id == 0:
			return
		is_local = player_data.is_local()
var player_data: PlayerData:
	get:
		return PlayerManager.get_player_by_id(player_id)

@export var mouse_sensitivity: float = 0.003

@export_group("Stamina")
@export var max_stamina: float = 100.0
## Stamina drained per second while sprinting (~4.5 seconds of continuous sprinting).
@export var stamina_drain_rate: float = 22.0
## Stamina recovered per second when not sprinting (~2.5 seconds to full recovery).
@export var stamina_regen_rate: float = 40.0

var stamina: float = 100.0

@onready var sight_pivot: Node3D = %SightPivot


func _ready() -> void:
	super()
	assert(player_id)
	assert(inventory)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	PlayerManager.register_player_node(self)

	stamina = max_stamina
	camera = %Camera3D

	if is_local:
		%Camera3D.make_current()
		%ItemInventoryUI.show()
		if HUD.instance:
			HUD.instance.set_stamina(1.0)
		$Visual/guy/Armature/Skeleton3D/Head.hide()
		$Visual/guy/Armature/Skeleton3D/Body.hide()


func _process(delta: float) -> void:
	super(delta)
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
	super(delta)
	if not is_local or is_ragdolled:
		return

	if Input.is_action_pressed("sprint"):
		stamina = maxf(stamina - stamina_drain_rate * delta, 0.0)
	else:
		stamina = minf(stamina + stamina_regen_rate * delta, max_stamina)

	if HUD.instance:
		HUD.instance.set_stamina(stamina / max_stamina)

	%RunParticles.emitting = is_sprinting and is_on_floor()
	%Camera3D.fov = lerpf(%Camera3D.fov, 105, 0.1) if is_sprinting else lerpf(%Camera3D.fov, 75, 0.1)


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


func _update_locomotion() -> void:
	_jumping()
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_down")
	if HUD.instance and HUD.instance.is_blocking_input():
		input_dir = Vector2.ZERO
	locomotion.desired_direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var sprint_held := Input.is_physical_key_pressed(KEY_SHIFT) and Input.is_action_pressed("sprint")
	locomotion.run_requested = sprint_held and locomotion.desired_direction != Vector3.ZERO


func can_sprint() -> bool:
	return stamina > 0.0 and status.can_sprint()


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


func _on_hit_received(damage: float) -> void:
	if not is_local:
		return
	if randf() < Combat.item_drop_chance(damage):
		_spawn_knocked_item()
	if is_instance_valid(camera):
		camera.add_damage_impact(damage)
	# Put the camera away before the knock; camera_out replicates to every peer.
	if equipment != null and equipment.camera_out:
		equipment.camera_out = false


func _jumping() -> void:
	if Input.is_action_just_pressed("jump"):
		if HUD.instance and HUD.instance.is_blocking_input():
			return
		if locomotion.do_jump():
			_rpc_play_sfx.rpc("jump")
	elif Input.is_action_just_released("jump"):
		locomotion.cut_jump()


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
	(inventory as PlayerInventory).drop_random_item(global_position + Vector3.UP, force)


func _to_string() -> String:
	return "Player: %s" % str(player_data)
