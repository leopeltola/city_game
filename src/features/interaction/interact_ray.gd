extends RayCast3D

@export var player: Player = null


func _ready() -> void:
	assert(player, "InteractionRay doesn't have Player set")


func _process(_delta: float) -> void:
	if is_colliding():
		var col = get_collider()
		if not col is Interactable:
			return
		var i: Interactable = col as Interactable
		%Label.show()
		%Label.text = i.get_prompt()
	else:
		%Label.hide()
		

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("e") and is_colliding():
		var col = get_collider()
		if not col is Interactable:
			return
		var i: Interactable = col as Interactable
		if not i.can_interact(player.player_id):
			return
		i.interact(player.player_id)
