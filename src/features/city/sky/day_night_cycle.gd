@tool
class_name DayNightCycle
extends Node

## Duration of a complete 24-hour day in seconds.
@export var day_length_seconds: float = 300.0

## Current hour of the day (0.0 to 24.0).
@export_range(0.0, 24.0, 0.05) var time_of_day: float = 8.0:
	set(val):
		time_of_day = val
		_update_lighting()

## Horizontal angle offset for the sun and moon path.
@export_range(-180.0, 180.0, 1.0) var azimuth: float = -30.0

## Primary daylight source. Must be first in the scene tree to bind to LIGHT0.
@export var sun_light: DirectionalLight3D

## Secondary nightlight source (optional).
@export var moon_light: DirectionalLight3D

## Peak light energy at midday.
@export var sun_max_energy: float = 1.0

## Peak light energy at midnight.
@export var moon_max_energy: float = 0.2


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	time_of_day = fmod(time_of_day + (delta / day_length_seconds) * 24.0, 24.0)
	_update_lighting()


## Manually sets the time of day and recalculates light rotations immediately.
func set_time(new_time: float) -> void:
	time_of_day = fmod(new_time, 24.0)
	_update_lighting()


func _update_lighting() -> void:
	var progress := time_of_day / 24.0
	var sun_pitch := (progress * -TAU) + (PI * 0.5)
	var sun_rot := Vector3(sun_pitch, deg_to_rad(azimuth), 0.0)

	if sun_light:
		sun_light.rotation = sun_rot
		var sun_height := -sin(sun_pitch)
		sun_light.light_energy = clampf(sun_height * 2.0, 0.0, 1.0) * sun_max_energy

	if moon_light:
		moon_light.rotation = Vector3(sun_pitch + PI, deg_to_rad(azimuth), 0.0)
		var moon_height := sin(sun_pitch)
		moon_light.light_energy = clampf(moon_height * 2.0, 0.0, 1.0) * moon_max_energy
