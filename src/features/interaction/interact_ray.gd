extends RayCast3D

@export var player: Player = null


func _ready() -> void:
	assert(player, "InteractionRay doesn't have Player set")


func _process(_delta: float) -> void:
	if not player.is_local:
		return
	if is_colliding():
		var col = get_collider()
		if not col is Interactable:
			hide_label()
			return
		var i: Interactable = col as Interactable
		if i.active:
			show_label(i.get_prompt(player.player_id))
		else:
			hide_label()

	else:
		hide_label()


func show_label(text: String) -> void:
	if not HUD.instance:
		return
	HUD.instance.show_interact_label(text)


func hide_label() -> void:
	if not HUD.instance:
		return
	HUD.instance.hide_interact_label()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("e") and is_colliding():
		var col = get_collider()
		if not col is Interactable:
			return
		var i: Interactable = col as Interactable
		if not i.can_interact(player.player_id):
			return
		i.interact(player.player_id)
