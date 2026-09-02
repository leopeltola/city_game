extends ItemEquip

## Emitted on the local client when an attack hits an entity.
signal hit_registered(target: Node3D, point: Vector3)

enum State {
	IDLE,
	ATTACKING,
	BLOCKING,
}

@export var damage: float = 25.0

@onready var _shape_cast: ShapeCast3D = %ShapeCast3D

var _state: State = State.IDLE
var _prev_cast_pos: Vector3
var _hit_targets: Array[Node3D] = []


func _ready() -> void:
	super()
	player.shown_item = "bat"
	_shape_cast.enabled = false
	_shape_cast.add_exception(player.hittable_area)


func _exit_tree() -> void:
	if player.shown_item == "bat":
		player.shown_item = ""


func _physics_process(_delta: float) -> void:
	if not player.is_local or _state != State.ATTACKING:
		return

	# Sweep backwards along the path the weapon just traveled
	_shape_cast.target_position = _shape_cast.to_local(_prev_cast_pos)
	_shape_cast.force_shapecast_update()

	for i in _shape_cast.get_collision_count():
		var collider: Object = _shape_cast.get_collider(i)
		if collider not in _hit_targets:
			_hit_targets.append(collider)
			hit_registered.emit(collider, _shape_cast.get_collision_point(i))
			
			var col_parent: Node3D = collider.get_parent()
			if col_parent.has_method("get_hit"):
				if col_parent.get("is_blocking") == true:
					print("Blocked!")
				else:
					var force: Vector3 = (collider.global_position - player.global_position).normalized() * 10.0
					force.y += 2.0
					col_parent.get_hit(0, force)

	_prev_cast_pos = _shape_cast.global_position


func _unhandled_input(event: InputEvent) -> void:
	if not player.is_local:
		return
	if event.is_action_pressed("left_click") and _state == State.IDLE:
		_request_attack()
		return
	if event.is_action_pressed("right_click") and _state == State.IDLE:
		_request_block()


func _request_attack() -> void:
	_rpc_attack.rpc()


func _request_block() -> void:
	_rpc_block.rpc()


@rpc("any_peer", "call_local", "reliable")
func _rpc_attack() -> void:
	_state = State.ATTACKING
	player.look_drag_multiplier = 0.3
	player.move_speed_multiplier = 0.75

	if player.is_local:
		_hit_targets.clear()
		_prev_cast_pos = _shape_cast.global_position
		_shape_cast.enabled = true

	await player.play_override_animation("bat_attack")

	if player.is_local:
		_shape_cast.enabled = false

	player.look_drag_multiplier = 1.0
	player.move_speed_multiplier = 1.0
	_state = State.IDLE


@rpc("any_peer", "call_local", "reliable")
func _rpc_block() -> void:
	_state = State.BLOCKING
	player.is_blocking = true
	player.look_drag_multiplier = 0.3
	
	player.play_override_animation("bat_block")
	await get_tree().create_timer(0.6).timeout
	player.is_blocking = false
	await get_tree().create_timer(0.5).timeout
	
	_state = State.IDLE
	player.look_drag_multiplier = 1.0
