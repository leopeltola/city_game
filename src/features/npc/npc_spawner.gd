class_name NpcSpawner
extends Node3D
## Server-side spawner for NPCs. Uses a MultiplayerSpawner so every peer instantiates
## the same Npc scene; the server owns and simulates them (authority = peer 1).

const CitizenScene := preload("res://src/features/npc/citizen/citizen.tscn")

## Scene spawned by this node. Defaults to a citizen; set police.tscn for officers.
@export var npc_scene: PackedScene = CitizenScene
## How many NPCs to spawn on ready.
@export var spawn_count := 1
## Local spawn position relative to this node (players spawn near the origin).
@export var spawn_position := Vector3.ZERO
## Scatter radius around spawn_position applied to each spawned NPC.
@export var spawn_radius := 0.0

var _next_id := 0


func _ready() -> void:
	%MultiplayerSpawner.spawn_function = _spawn_func
	if Net.is_server:
		# Defer one frame so clients are ready to receive the spawn (mirrors PlayerSpawner).
		await get_tree().process_frame
		for i in spawn_count:
			spawn_npc()


## Spawns one NPC at the configured position. Server only.
func spawn_npc() -> void:
	if not Net.is_server:
		return

	var offset := Vector3.ZERO
	if spawn_radius > 0.0:
		var angle := randf() * TAU
		var radius := sqrt(randf()) * spawn_radius
		offset = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

	%MultiplayerSpawner.spawn({ "id": _next_id, "offset": offset })
	_next_id += 1


func _spawn_func(data: Dictionary) -> Node:
	var npc: Npc = npc_scene.instantiate()
	npc.name = "Npc_%s" % data["id"]
	npc.position = spawn_position + (data["offset"] as Vector3)
	return npc
