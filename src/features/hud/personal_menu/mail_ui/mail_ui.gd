extends MarginContainer

const MailRowItemScene := preload("res://src/features/hud/personal_menu/mail_ui/mail_row_item.tscn")


func _ready() -> void:
	visibility_changed.connect(
		func():
			if visible:
				for c in %MailContainer.get_children():
					c.queue_free()
				var msgs := MessageManager.get_local_messages()
				for msg in msgs:
					var item := MailRowItemScene.instantiate()
					item.set_message(msg)
					%MailContainer.add_child(item)
	)
