extends Node3D

@export var shown_item: ItemType






func _ready():
	if shown_item:
		var item_instance = shown_item.get_display_item_scene().instantiate()
		%ClothingContainer.add_child(item_instance)
		$mannequin/Mannequinbody.hide()
