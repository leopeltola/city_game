extends Interactable

@onready var world_item: ItemWorld = get_parent()


func _ready() -> void:
	assert(world_item != null)


func get_prompt(_player_id: int) -> String:
	return world_item.get_prompt(_player_id)


func interact(player_id: int) -> void:
	interacted.emit(player_id)
