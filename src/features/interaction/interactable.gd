class_name Interactable
extends CollisionObject3D

signal interacted(player_id: int)

@export var prompt: String = "Interact"


func get_prompt() -> String:
	return "prompt"


func interact(player_id: int) -> void:
	print("Player %s interacted with %s" % [player_id, self])
	interacted.emit(player_id)


func can_interact(player_id: int) -> bool:
	return true
