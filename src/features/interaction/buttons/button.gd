extends Interactable
class_name InteractableButton

## Press click, played locally for the interacting player.
const PRESS_SFX: AudioStream = preload("res://assets/sfx/slot_machine/button_lock.ogg")

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
	Audio.play_sfx_3d(PRESS_SFX, global_position, -6.0, 15.0)
	if toggleable:
		toggle_down = not toggle_down
		toggled.emit(toggle_down)
	interacted.emit(player_id)
