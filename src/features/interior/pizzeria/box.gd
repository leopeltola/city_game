extends Node3D


func _ready():
	%BoxInteractableArea.interacted.connect(_on_interacted)

func _on_interacted(player_id: int) -> void:
	add_pizza_box_to_inventory(player_id)

func add_pizza_box_to_inventory(player_id) -> void:
	var id: int = ItemManager.create_item_of_type("pizza_box")
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	var inv := player.inventory as PlayerInventory
	if inv == null or not inv.try_add_item(id):
		return # no space in inv, abort
