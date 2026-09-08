extends Node3D

## Emitted whenever the button changes its pressed state.
signal toggled(is_pressed: bool)

@export var up_prompt := ""
@export var down_prompt := ""

## Toggles whether the button can be interacted with.
@export var pressable := true:
	set(val):
		pressable = val
		%Button.active = pressable

var _pressed_down := false:
	set(val):
		if _pressed_down == val:
			return
		_pressed_down = val
		_animate_press(_pressed_down)
		toggled.emit(_pressed_down)
		if up_prompt and not _pressed_down:
			%Button.prompt = up_prompt
		elif down_prompt and _pressed_down:
			%Button.prompt = down_prompt
		else:
			%Button.prompt = "Press"

var _tween: Tween
@onready var _button: Node3D = %Button
@onready var _initial_pos: Vector3 = _button.position


func _ready() -> void:
	$Button.interacted.connect(
		func(_player_id: int) -> void:
			toggle()
	)


## Returns true if the button is currently in the pressed-down state.
func is_pressed_down() -> bool:
	return _pressed_down


## Sets the pressed state over the network.
func set_pressed_down(value: bool) -> void:
	_rpc_set_pressed_down.rpc(value)


## Toggles the button between pressed and unpressed states.
func toggle() -> void:
	set_pressed_down(not _pressed_down)


@rpc("any_peer", "reliable", "call_local")
func _rpc_set_pressed_down(value: bool) -> void:
	_pressed_down = value

## Animates the button's position and scale on interaction.
func _animate_press(down: bool) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()

	_tween = create_tween().set_parallel(true)

	var target_pos := _initial_pos + (Vector3(0.0, -0.025, 0.0) if down else Vector3.ZERO)
	var squash_scale := Vector3(1.1, 0.85, 1.1) if down else Vector3(0.95, 1.05, 0.95)

	_tween.tween_property(_button, "position", target_pos, 0.35) \
			.set_trans(Tween.TRANS_BACK if down else Tween.TRANS_ELASTIC) \
			.set_ease(Tween.EASE_OUT)

	_tween.tween_property(_button, "scale", squash_scale, 0.017) \
			.set_trans(Tween.TRANS_QUAD) \
			.set_ease(Tween.EASE_OUT)
			
	_tween.tween_property(_button, "scale", Vector3.ONE, 0.25) \
			.set_trans(Tween.TRANS_ELASTIC) \
			.set_ease(Tween.EASE_OUT) \
			.set_delay(0.017)
