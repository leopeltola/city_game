class_name MessagesToast
extends MarginContainer
## Displays message toasts, replacing the current one immediately when a new message arrives.

const TOAST_SCENE: PackedScene = preload("res://src/features/hud/personal_menu/mail_ui/message_toast_item.tscn")
const DISPLAY_DURATION: float = 5.0
const EXIT_DURATION: float = 0.18

@onready var toast_container: MarginContainer = %ToastContainer

var _current_toast: ToastItem = null
var _current_tween: Tween = null


func _ready() -> void:
	MessageManager.message_received.connect(_on_message_received)


## Shows a toast notification, immediately replacing any toast currently on screen.
func show_msg_toast(sender: String, title: String, msg: String) -> void:
	_dismiss_current_toast()

	var toast: ToastItem = TOAST_SCENE.instantiate() as ToastItem
	toast_container.add_child(toast)
	toast.set_toast(sender, title, msg)
	_current_toast = toast

	_animate_toast(toast)


## Quickly slides the current toast out and frees it so a new one can take its place.
func _dismiss_current_toast() -> void:
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()
	_current_tween = null

	var toast: ToastItem = _current_toast
	_current_toast = null
	if not is_instance_valid(toast):
		return

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(toast, "position:x", 260.0, EXIT_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(toast, "rotation_degrees", 8.0, EXIT_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(toast, "scale", Vector2(0.7, 1.3), EXIT_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(toast, "modulate:a", 0.0, EXIT_DURATION)
	tween.chain().tween_callback(toast.queue_free)


func _animate_toast(toast: Control) -> void:
	toast.pivot_offset = Vector2(208.0 * 0.5, toast.size.y * 0.5)

	# Enter offscreen right with directional squash and tilt
	toast.position.x = 260.0
	toast.rotation_degrees = 8.0
	toast.scale = Vector2(0.7, 1.3)
	toast.modulate.a = 0.0

	var tween: Tween = create_tween()
	_current_tween = tween

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

	# Cleanup
	tween.chain().tween_callback(_on_toast_finished.bind(toast))


func _on_toast_finished(toast: ToastItem) -> void:
	if is_instance_valid(toast):
		toast.queue_free()
	if _current_toast == toast:
		_current_toast = null
		_current_tween = null


func _on_message_received(message) -> void:
	print(message, PlayerManager.get_local_player_or_null())
	show_msg_toast(message["sender"], message["title"], message["msg"])
