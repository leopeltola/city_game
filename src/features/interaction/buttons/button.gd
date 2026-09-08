extends Interactable
class_name InteractableButton

signal toggled(down: bool)

@export var toggleable := false

var toggle_down := false:
	set(val):
		if toggle_down == val:
			return
		toggle_down = val
		if toggle_down:
			$AnimationPlayer.play("down")
		else:
			$AnimationPlayer.play("up")


func interact(player_id: int) -> void:
	if toggleable:
		toggle_down = not toggle_down
		toggled.emit(toggle_down)
	interacted.emit(player_id)
