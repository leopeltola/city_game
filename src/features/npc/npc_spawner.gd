extends Node3D
## Server-side spawner for NPCs. Uses a MultiplayerSpawner so every peer instantiates
## the same Npc scene; the server owns and simulates them (authority = peer 1).

const NpcScene := preload("res://src/features/npc/citizen.tscn")

## Local spawn position relative to this node (players spawn near the origin).
@export var spawn_position := Vector3.ZERO

var _next_id := 0


func _ready() -> void:
	%MultiplayerSpawner.spawn_function = _spawn_func
	if Net.is_server:
		# Defer one frame so clients are ready to receive the spawn (mirrors PlayerSpawner).
		await get_tree().process_frame
		spawn_npc()


## Spawns one NPC at the configured position. Server only.
func spawn_npc() -> void:
	if not Net.is_server:
		return
	%MultiplayerSpawner.spawn(_next_id)
	_next_id += 1


func _spawn_func(npc_id: int) -> Node:
	var npc: Npc = NpcScene.instantiate()
	npc.name = "Npc_%s" % npc_id
	npc.position = spawn_position
	return npc
