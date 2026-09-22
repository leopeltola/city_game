@tool
extends Node3D

@onready var occluder: OccluderInstance3D = %OccluderInstance3D

## Available base modules.
@export var bases: Array[BuildingPart] = []
## Available story modules.
@export var stories: Array[BuildingPart] = []
## Available roof modules.
@export var roofs: Array[BuildingPart] = []
## Maximum number of middle stories to generate.
@export_range(0, 20, 1) var max_stories: int = 3

@export var main_color: Color = Color(0.907, 0.92, 0.846, 1.0):
	set(val):
		if main_color == val:
			return
		main_color = val
		_update_colors()

@export var secondary_color: Color = Color(0.334, 0.424, 0.44, 1.0):
	set(val):
		if secondary_color == val:
			return
		secondary_color = val
		_update_colors()

## Triggers generation inside the Godot editor inspector.
@export_tool_button("Generate", "MeshInstance3D") var generate_action: Callable = generate_building
## Randomizes the main and secondary colors using stylized HSV harmonies.
@export_tool_button("Randomize Colors", "Color") var randomize_colors_action: Callable = randomize_colors


func _ready() -> void:
	_apply_colors(self)


## Clears existing generated children and stacks a base, random stories, and a roof.
func generate_building() -> void:
	_clear_children()

	var current_height := 0.0

	if not bases.is_empty():
		var base_part := bases.pick_random() as BuildingPart
		current_height += _spawn_part(base_part, current_height)

	if not stories.is_empty() and max_stories > 0:
		var story_count := randi_range(0, max_stories)
		for _i in story_count:
			var story_part := stories.pick_random() as BuildingPart
			current_height += _spawn_part(story_part, current_height)

	if not roofs.is_empty():
		var roof_part := roofs.pick_random() as BuildingPart
		current_height += _spawn_part(roof_part, current_height)
	
	if occluder:
		var box: BoxOccluder3D = occluder.occluder
		box.size.y = current_height
		occluder.position.y = current_height * 0.5


## Generates a new color scheme using Monochromatic, Analogous, or Complementary color harmonies.
func randomize_colors() -> void:
	var base_h := randf()
	var base_s := randf_range(0.1, 0.5)
	var base_v := randf_range(0.6, 0.95)

	var sec_h := base_h
	var harmony := randi() % 3

	if harmony == 1:
		sec_h = wrapf(base_h + randf_range(0.1, 0.15) * (1 if randi() % 2 == 0 else -1), 0.0, 1.0)
	elif harmony == 2:
		sec_h = wrapf(base_h + 0.5, 0.0, 1.0)

	var sec_s := clampf(base_s + randf_range(0.2, 0.4), 0.0, 1.0)
	var sec_v := clampf(base_v - randf_range(0.3, 0.6), 0.1, 1.0)

	main_color = Color.from_hsv(base_h, base_s, base_v)
	secondary_color = Color.from_hsv(sec_h, sec_s, sec_v)


func _spawn_part(part: BuildingPart, y_offset: float) -> float:
	if not part or not part.scene:
		return 0.0

	var instance := part.scene.instantiate() as Node3D
	if not instance:
		return 0.0

	instance.name = "Module_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 10000)
	add_child(instance, true)
	instance.position.y = y_offset

	var scene_root := get_tree().edited_scene_root if Engine.is_editor_hint() else owner
	if scene_root:
		instance.owner = scene_root

	_apply_colors(instance)
	return part.height


func _clear_children() -> void:
	for child in get_children():
		if child is OccluderInstance3D:
			continue
		remove_child(child)
		child.queue_free()


func _update_colors() -> void:
	_apply_colors(self)


func _apply_colors(node: Node) -> void:
	if node is MeshInstance3D:
		node.set_instance_shader_parameter("main_color", main_color)
		node.set_instance_shader_parameter("secondary_color", secondary_color)

	for child in node.get_children():
		_apply_colors(child)
