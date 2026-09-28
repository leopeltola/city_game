@tool
extends Path3D

enum Type {
	WHITE_FULL,
	WHITE_STRIPE,
	YELLOW_FULL,
	YELLOW_STRIPE,
}

@export var type: Type = Type.WHITE_FULL:
	set(val):
		if type == val:
			return
		type = val
		_update_visuals()

## Lateral width of the painted stroke in meters.
@export_range(0.02, 1.0, 0.01) var width: float = 0.2:
	set(val):
		if is_equal_approx(width, val):
			return
		width = val
		_update_polygon()


func _ready() -> void:
	_update_polygon()
	_update_visuals()


func _update_polygon() -> void:
	if not is_inside_tree():
		return
	var half := width * 0.5
	%CSGPolygon3D.polygon = PackedVector2Array([
		Vector2(0.0, -0.1),
		Vector2(-half, 0.01),
		Vector2(half, 0.001),
	])


func _update_visuals() -> void:
	if not is_inside_tree():
		return
	var color := Color.ORANGE if type in [Type.YELLOW_FULL, Type.YELLOW_STRIPE] else Color(0.794, 0.794, 0.794, 1.0)
	var stripe_val := 0.6 if type in [Type.YELLOW_STRIPE, Type.WHITE_STRIPE] else 0.0
	%CSGPolygon3D.set_instance_shader_parameter("albedo", color)
	%CSGPolygon3D.set_instance_shader_parameter("stripes", stripe_val)
