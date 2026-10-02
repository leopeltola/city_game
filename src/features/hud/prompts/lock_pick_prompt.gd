extends Control

signal _resolved(result: bool)

## Duration of the pop-in played when the minigame appears.
const INTRO_TIME := 0.15


func _ready():
	%ExitButton.pressed.connect(_cancel)


func prompt() -> bool:
	if visible:
		_cancel()
	var _prev_mouse_mode := Input.mouse_mode
	if _prev_mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show()
	_play_intro()
	%SubViewport.render_target_update_mode = PROCESS_MODE_ALWAYS
	%LockPickingScene.process_mode = Node.PROCESS_MODE_INHERIT
	%LockPickingScene.initialize_lock()
	%ExitButton.grab_focus()

	var res: bool = await _resolved
	hide()
	%SubViewport.render_target_update_mode = PROCESS_MODE_DISABLED
	%LockPickingScene.process_mode = Node.PROCESS_MODE_DISABLED
	Input.mouse_mode = _prev_mouse_mode
	return res


## Zooms the minigame in from the screen center instead of snapping on. Scale only: the
## full-screen SubViewport does not reliably pick up a modulate fade.
func _play_intro() -> void:
	pivot_offset = size * 0.5
	scale = Vector2(0.96, 0.96)
	create_tween().tween_property(self, "scale", Vector2.ONE, INTRO_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _cancel() -> void:
	if _resolved.get_connections().is_empty():
		return
	_resolved.emit(false)
