extends MarginContainer

const COLOR_EMPTY := Color(0.1, 0.1, 0.1)
const COLOR_FILLED := Color(0.5, 0.5, 0.5)
const COLOR_ACTIVE_EMPTY := Color(0.3, 0.3, 0.3)
const COLOR_ACTIVE_FILLED := Color(0.8, 0.8, 0.8)

@export var inv: PlayerInventory = null

@onready var slots: Array[ColorRect] = [
	%"1",
	%"2",
	%"3",
	%"4",
]


func _ready() -> void:
	inv.inventory_updated.connect(_update)
	await get_tree().process_frame
	_update()


func _update() -> void:
	for i in slots.size():
		var slot := slots[i]
		var is_active := (i == inv.active_index)
		var is_occupied := (inv.get_item_at_idx(i) != -1)

		if is_occupied:
			slot.color = COLOR_ACTIVE_FILLED if is_active else COLOR_FILLED
		else:
			slot.color = COLOR_ACTIVE_EMPTY if is_active else COLOR_EMPTY
