class_name MessagesToast
extends MarginContainer
## Displays queued message toasts sequentially with pop-in animations.

const TOAST_SCENE: PackedScene = preload("res://src/features/hud/personal_menu/mail_ui/message_toast_item.tscn")
const DISPLAY_DURATION: float = 5.0

@onready var toast_container: MarginContainer = %ToastContainer

var _queue: Array[Dictionary] = []
var _is_displaying: bool = false


func _ready() -> void:
	MessageManager.message_received.connect(_on_message_received)


## Queues a toast notification. Shows immediately if no toast is currently active.
func queue_msg_toast(sender: String, title: String, msg: String) -> void:
	_queue.append({ "sender": sender, "title": title, "msg": msg })
	if not _is_displaying:
		_process_next_toast()


func _process_next_toast() -> void:
	if _queue.is_empty():
		_is_displaying = false
		return

	_is_displaying = true
	var data: Dictionary = _queue.pop_front()

	var toast: ToastItem = TOAST_SCENE.instantiate() as ToastItem
	toast_container.add_child(toast)
	toast.set_toast(data.sender, data.title, data.msg)

	_animate_toast(toast)


func _animate_toast(toast: Control) -> void:
	toast.pivot_offset = Vector2(208.0 * 0.5, toast.size.y * 0.5)

	# Enter offscreen right with directional squash and tilt
	toast.position.x = 260.0
	toast.rotation_degrees = 8.0
	toast.scale = Vector2(0.7, 1.3)
	toast.modulate.a = 0.0

	var tween: Tween = create_tween()

	# Entrance: Snap in from right, then settle with an overshoot squash
	tween.set_parallel(true)
	tween.tween_property(toast, "position:x", 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(toast, "rotation_degrees", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(toast, "scale", Vector2(1.15, 0.85), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(toast, "modulate:a", 1.0, 0.2)

	# Settle back to neutral
	tween.chain().tween_property(toast, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Display duration
	tween.tween_interval(DISPLAY_DURATION)

	# Exit: Anticipation dip, then snap out to the right
	tween.chain().tween_property(toast, "scale", Vector2(1.15, 0.85), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	tween.chain().set_parallel(true)
	tween.tween_property(toast, "position:x", 260.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(toast, "rotation_degrees", 8.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(toast, "scale", Vector2(0.7, 1.3), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(toast, "modulate:a", 0.0, 0.25)

	# Cleanup and chain
	tween.chain().tween_callback(toast.queue_free)
	tween.tween_callback(_process_next_toast)



func _on_message_received(message) -> void:
	print(message, PlayerManager.get_local_player_or_null())
	queue_msg_toast(message["sender"], message["title"], message["msg"])
