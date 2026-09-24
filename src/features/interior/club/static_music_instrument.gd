extends Node3D
class_name StaticMusicInstrument


@export var animation_name : String



func get_facing_direction() -> Vector3:
	return %FacingPos.global_position - self.global_position
