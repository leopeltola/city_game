class_name ItemMultiplayerSpawner
extends MultiplayerSpawner

static var instance: ItemMultiplayerSpawner = null


func _ready() -> void:
	ItemMultiplayerSpawner.instance = self
	spawn_function = _spawn_function


func _exit_tree() -> void:
	if ItemMultiplayerSpawner.instance == self:
		ItemMultiplayerSpawner.instance = null


func _spawn_function(data: Dictionary) -> Node:
	print("_spawn_function of ItemMultiplayerSpawner called")
	var node := MeshInstance3D.new()
	node.mesh = SphereMesh.new()
	node.position = data["position"]
	return node
