extends Control

signal _resolved(result: bool)


func _ready():
	%ExitButton.pressed.connect(_cancel)


func prompt() -> bool:
	if visible:
		_cancel()
	var _prev_mouse_mode := Input.mouse_mode
	if _prev_mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show()
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

func _cancel() -> void:
	if _resolved.get_connections().is_empty():
		return
	_resolved.emit(false)
