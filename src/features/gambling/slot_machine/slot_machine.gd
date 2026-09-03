extends Node3D

@onready var wheels: Array[Node3D] = [
	$slot_machine/Wheel1,
	$slot_machine/Wheel2,
	$slot_machine/Wheel3,
]


func _ready() -> void:
	$LevelInteract.interacted.connect(_lever_pulled)


func _lever_pulled(_player_id: int) -> void:
	_rpc_level_pulled.rpc()


@rpc("any_peer", "reliable", "call_local")
func _rpc_level_pulled() -> void:
	$LevelInteract.prompt = ""
	$LevelInteract.active = false
	%LevelAnimationPlayer.play("pull_level")
	await %LevelAnimationPlayer.animation_finished
	$LevelInteract.prompt = "Play"
	$LevelInteract.active = true
