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
	var node: ItemWorld = ItemManager.get_item_type(data["type"]).get_world_item_scene().instantiate()
	node.position = data["position"]
	node.rotation = data["rotation"]
	node.item_id = data["id"]
	node.launch_force = data.get("launch_force", Vector3.ZERO)
	node.owner_player_id = data.get("owner", 0)

	return node
