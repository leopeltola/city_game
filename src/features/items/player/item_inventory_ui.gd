extends MarginContainer

@export var inv: PlayerInventory = null

@onready var slots: Array[ColorRect] = [
	%"1",
	%"2",
	%"3",
	%"4",
]


func _ready() -> void:
	inv.active_item_changed.connect(_on_item_equipped)


func _on_item_equipped() -> void:
	_update()


func _update() -> void:
	for i in range(slots.size()):
		var slot: ColorRect = slots[i]
		var item_id: int = inv.get_item_at_idx(i)
		if item_id == -1:
			slot.color = Color(0.1, 0.1, 0.1)
			if i == inv.active_index:
				slot.color = Color(0.5, 0.5, 0.5)
		else:
			slot.color = Color(0.5, 0.5, 0.5)
			if i == inv.active_index:
				slot.color = Color(0.8, 0.8, 0.8)
