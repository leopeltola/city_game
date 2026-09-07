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


func set_message(msg: Dictionary) -> void:
	%Sender.text = msg["sender"]
	%Title.text = msg["title"]
