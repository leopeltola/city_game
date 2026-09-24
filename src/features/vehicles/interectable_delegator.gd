extends Interactable

## The node to which the requests are forwarded to
@export var handler: Node = null


func get_prompt(player_id: int) -> String:
	assert(handler)
	return handler.get_prompt(player_id)


func can_interact(player_id: int) -> bool:
	assert(handler)
	return handler.can_interact(player_id)


func interact(player_id: int) -> void:
	assert(handler)
	handler.interact(player_id)
