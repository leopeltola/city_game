class_name CashVisual
extends RefCounted
## Shared bill appearance for cash stacks: maps a money amount to the shader's bill
## count, texture index and tint. Used by both the world ([ItemWorld]) and held
## ([ItemEquip]) variants of a cash stack so they stay in sync.

## Per-denomination bill tints, indexed by [_index_for].
const BILL_COLORS: Array[Color] = [
	Color(0.214, 0.299, 0.33, 1.0),
	Color(0.33, 0.191, 0.275, 1.0),
	Color(0.106, 0.15, 0.33, 1.0),
	Color(0.33, 0.247, 0.175, 1.0),
	Color(0.086, 0.22, 0.171, 1.0),
	Color(0.28, 0.256, 0.098, 1.0),
	Color(0.24, 0.13, 0.25, 1.0),
]


## Applies the amount's bill appearance to [param cash_mesh], the Cash mesh whose
## material exposes the bill_amount / texture_index / text_color shader parameters.
static func apply(cash_mesh: MeshInstance3D, amount: int) -> void:
	if cash_mesh == null:
		return
	var index := _index_for(amount)
	cash_mesh.set_instance_shader_parameter("bill_amount", amount)
	cash_mesh.set_instance_shader_parameter("texture_index", index)
	cash_mesh.set_instance_shader_parameter("text_color", BILL_COLORS[index])


static func _index_for(amount: int) -> int:
	if amount < 10:
		return 0
	if amount < 20:
		return 1
	if amount < 50:
		return 2
	if amount < 100:
		return 3
	if amount < 200:
		return 4
	if amount < 500:
		return 5
	return 6
