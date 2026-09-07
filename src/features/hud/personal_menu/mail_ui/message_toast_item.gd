class_name ToastItem
extends PanelContainer
## Visual representation of a single toast entry.

@onready var _sender: Label = %Sender
@onready var _title: Label = %Title
@onready var _message: Label = %Message


## Populates the text elements of the toast.
func set_toast(sender: String, title: String, message: String) -> void:
	_sender.text = sender
	_title.text = title
	_message.text = message
