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


func _ready() -> void:
	_update_visuals()


func _update_visuals() -> void:
	var color := Color.ORANGE if type in [Type.YELLOW_FULL, Type.YELLOW_STRIPE] else Color(0.794, 0.794, 0.794, 1.0)
	var stripe_val := 0.6 if type in [Type.YELLOW_STRIPE, Type.WHITE_STRIPE] else 0.0
	$CSGPolygon3D.set_instance_shader_parameter("albedo", color)
	$CSGPolygon3D.set_instance_shader_parameter("stripes", stripe_val)
