extends ItemEquip

@onready var anim: AnimationPlayer = %AnimationPlayer


func _ready() -> void:
	super()
	print(get_multiplayer_authority())


func _unhandled_input(event: InputEvent) -> void:
	if not player.is_local:
		return
	if event.is_action_pressed("left_click"):
		_try_attack()


func _try_attack() -> void:
	_rpc_attack.rpc()


@rpc("any_peer", "call_local", "reliable")
func _rpc_attack():
	if anim.is_playing():
		return
	anim.play("attack")
