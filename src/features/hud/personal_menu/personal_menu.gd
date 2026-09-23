extends Control

@onready var _information: InformationUI = %Information

var _prev_mouse_mode: Input.MouseMode


func _ready() -> void:
	%CloseButton.pressed.connect(
		func():
			hide()
	)
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	if visible:
		_prev_mouse_mode = Input.mouse_mode
		if _prev_mouse_mode != Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_information.refresh()
	else:
		Input.mouse_mode = _prev_mouse_mode


func set_tab(tab: StringName) -> void:
	match tab:
		"info":
			%TabContainer.current_tab = 0
			_information.refresh()
		"messages":
			%TabContainer.current_tab = 1
		_:
			assert(false, "Tab '%s' not found in PersonalMenu" % tab)
