extends CanvasLayer

const ToastScene := preload("res://src/utilities/toast_overlay/toast.tscn")

@onready var toast_container: VBoxContainer = %ToastContainer


func show_info(msg: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var toast := ToastScene.instantiate()
	toast.text = msg
	toast_container.add_child(toast)
