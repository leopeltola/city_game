extends ItemEquip

## Emitted on the local client when an attack hits an entity.
signal hit_registered(target: Node3D, point: Vector3)

enum State { IDLE, ATTACKING, BLOCKING }

@export var hit_sound: AudioStream = null
@export var block_sound: AudioStream = null

@export var damage: float = 25.0
@onready var _shape_cast: ShapeCast3D = %ShapeCast3D

var _state: State = State.IDLE
var _prev_cast_pos: Vector3
var _hit_targets: Array[Node3D] = []
var _attack_start_msec: int = 0


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
					_rpc_interrupt_state.rpc(0.85)
					if col_parent.has_method("trigger_block_success"):
						col_parent.trigger_block_success()
					Audio.play_sfx(block_sound)
				else:
					_rpc_interrupt_state.rpc(0.1)
					var force: Vector3 = (collider.global_position - player.global_position).normalized() * 10.0
					force.y += 2.0
					col_parent.get_hit(damage, force)
					Audio.play_sfx(hit_sound)

	_prev_cast_pos = _shape_cast.global_position


func _unhandled_input(event: InputEvent) -> void:
	if not player.is_local:
		return
	if event.is_action_pressed("left_click") and _state == State.IDLE:
		_rpc_attack.rpc()
	elif event.is_action_pressed("right_click"):
		if _state == State.IDLE:
			_rpc_block.rpc()
		elif _state == State.ATTACKING and (Time.get_ticks_msec() - _attack_start_msec) <= 500:
			_rpc_interrupt_state.rpc(0.2)


func _reset_state(blend_time: float = 0.0) -> void:
	player.cancel_override_animation(blend_time)
	await get_tree().create_timer(blend_time).timeout
	_state = State.IDLE
	player.is_blocking = false
	player.look_drag_multiplier = 1.0
	player.move_speed_multiplier = 1.0
	if player.is_local:
		_shape_cast.enabled = false


@rpc("any_peer", "call_local", "reliable")
func _rpc_interrupt_state(blend_time: float) -> void:
	_reset_state(blend_time)


@rpc("any_peer", "call_local", "reliable")
func _rpc_attack() -> void:
	_state = State.ATTACKING
	_attack_start_msec = Time.get_ticks_msec()
	player.look_drag_multiplier = 0.3
	player.move_speed_multiplier = 0.75

	if player.is_local:
		_hit_targets.clear()
		_prev_cast_pos = _shape_cast.global_position
		_shape_cast.enabled = true

	await player.play_override_animation("bat_attack")
	if _state == State.ATTACKING:
		_reset_state(0.2)


@rpc("any_peer", "call_local", "reliable")
func _rpc_block() -> void:
	_state = State.BLOCKING
	player.is_blocking = true
	player.look_drag_multiplier = 0.3

	await player.play_override_animation("bat_block")
	if _state == State.BLOCKING:
		_reset_state(0.2)
