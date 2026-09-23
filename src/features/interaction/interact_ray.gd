extends RayCast3D

@export var player: Player = null


func _ready() -> void:
	assert(player, "InteractionRay doesn't have Player set")


func _process(_delta: float) -> void:
	if not player.is_local or (HUD.instance and HUD.instance.is_blocking_input()):
		return
	if is_colliding():
		var col = get_collider()
		if not col is Interactable:
			hide_label()
			return
		var i: Interactable = col as Interactable
		# An empty prompt (e.g. a jail door that is already open) means no action.
		var prompt := i.get_prompt(player.player_id) if i.active else ""
		if prompt.is_empty():
			hide_label()
		else:
			show_label(prompt)

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
	if not player.is_local or (HUD.instance and HUD.instance.is_blocking_input()):
		return
	if event.is_action_pressed("e") and is_colliding():
		var col = get_collider()
		if not col is Interactable:
			return
		var i: Interactable = col as Interactable
		if not i.can_interact(player.player_id):
			return
		# An interactable that can be used must show a prompt, otherwise the player
		# would trigger an action with no on-screen indication. Fails fast in dev.
		assert(
			not i.get_prompt(player.player_id).is_empty(),
			"Interactable '%s' is interactable but shows no prompt" % i.name,
		)
		i.interact(player.player_id)
