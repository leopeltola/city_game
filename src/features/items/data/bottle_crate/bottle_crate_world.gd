extends ItemWorld

@onready var bottles: Array[Node3D] = [
	%wine_bottle1,
	%wine_bottle2,
	%wine_bottle3,
	%wine_bottle4,
	%wine_bottle5,
	%wine_bottle6,
]

func _ready() -> void:
	super()
	
	var bottles_count: int= ItemManager.get_item_data(item_id, "bottles", 6)
	for i in 6-bottles_count:
		bottles[i].hide()
