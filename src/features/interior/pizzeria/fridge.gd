extends Node3D


func _ready():
	%FridgeInteractableArea.interacted.connect(_on_interacted)

func _on_interacted(player_id: int) -> void:
	add_sauce_to_inventory(player_id)

func add_sauce_to_inventory(player_id) -> void:
	var id: int = ItemManager.create_item_of_type("pizza_sauce")
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	var inv := player.inventory as PlayerInventory
	if inv == null or not inv.try_add_item(id):
		return # no space in inv, abort
