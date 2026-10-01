extends MarginContainer

func _ready() -> void:
	mouse_entered.connect(
		func():
			modulate = Color(0.903, 0.914, 0.931, 1.0)
	)
	mouse_exited.connect(
		func():
			modulate = Color.WHITE
	)
	gui_input.connect(
		func(event: InputEvent):
			if (
				event is InputEventMouseButton
				and event.button_index == MOUSE_BUTTON_LEFT
				and event.pressed
			):
				%Body.visible = not %Body.visible
	)


func set_message(msg: Dictionary) -> void:
	%Sender.text = msg["sender"]
	%Title.text = msg["title"]
	%Body.text = msg["msg"]
	%Body.visible = false
