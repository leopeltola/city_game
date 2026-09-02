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
var shown_item := ""

## Multiplier applied to mouse look sensitivity. Lower values simulate drag/resistance.
var look_drag_multiplier := 1.0
## Multiplier applied to movement speed.
var move_speed_multiplier := 1.0
var is_blocking := false

@export var walk_speed: float = 4.0
@export var jump_velocity: float = 6
@export var mouse_sensitivity: float = 0.003

@export var gravity: float = 15

@onready var sight_pivot: Node3D = %SightPivot
@onready var anim_player: AnimationPlayer = $Visual/guy/AnimationPlayer
@onready var hittable_area: Area3D = %HittableArea


func _ready() -> void:
	assert(player_id)
	assert(inventory)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	PlayerManager.register_player_node(self)

	if is_local:
		%Camera3D.make_current()
		%ItemInventoryUI.show()
		$Visual/guy/Armature/Skeleton3D/Head.hide()
		$Visual/guy/Armature/Skeleton3D/Body.hide()


func _unhandled_input(event: InputEvent) -> void:
	if not is_local:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var effective_sensitivity := mouse_sensitivity * look_drag_multiplier
		rotate_y(-event.relative.x * effective_sensitivity)
		sight_pivot.rotate_x(-event.relative.y * effective_sensitivity)
		sight_pivot.rotation.x = clamp(sight_pivot.rotation.x, deg_to_rad(-89), deg_to_rad(89))
	if event.is_action_pressed("e"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_released("e"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func play_override_animation(anim_name: String) -> void:
	_override_anim = anim_name
	anim_player.play(anim_name)
	await anim_player.animation_finished
	_override_anim = ""


## Applies damage and knockback force to the player.
func get_hit(_damage: float, force: Vector3) -> void:
	_rpc_get_hit.rpc(_damage, force)


@rpc("any_peer", "reliable")
func _rpc_get_hit(_damage: float, force: Vector3) -> void:
	velocity += force


func _process(_delta: float) -> void:
	if shown_item == "bat":
		if not _override_anim:
			anim_player.play("bat_hold")
	else:
		if not _override_anim:
			anim_player.play("idle")


func _physics_process(delta: float) -> void:
	if not is_local:
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var current_walk_speed := walk_speed * move_speed_multiplier
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var target_vel := direction * current_walk_speed
	var accel := 10.0 if direction else 8.0
	velocity.x = move_toward(velocity.x, target_vel.x, accel * delta * current_walk_speed)
	velocity.z = move_toward(velocity.z, target_vel.z, accel * delta * current_walk_speed)

	move_and_slide()


func _to_string() -> String:
	return "Player: %s" % str(player_data)
