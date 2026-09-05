@tool
extends Node3D

## Available base modules.
@export var bases: Array[BuildingPart] = []
## Available story modules.
@export var stories: Array[BuildingPart] = []
## Available roof modules.
@export var roofs: Array[BuildingPart] = []
## Maximum number of middle stories to generate.
@export_range(0, 20, 1) var max_stories: int = 3

## Triggers generation inside the Godot editor inspector.
@export_tool_button("Generate") var generate_action: Callable = generate_building


## Clears existing generated children and stacks a base, random stories, and a roof.
func generate_building() -> void:
	_clear_children()

	var current_height := 0.0

	# 1. Base
	if not bases.is_empty():
		var base_part := bases.pick_random() as BuildingPart
		current_height += _spawn_part(base_part, current_height)

	# 2. Middle Stories
	if not stories.is_empty() and max_stories > 0:
		var story_count := randi_range(0, max_stories)
		for _i in story_count:
			var story_part := stories.pick_random() as BuildingPart
			current_height += _spawn_part(story_part, current_height)

	# 3. Roof
	if not roofs.is_empty():
		var roof_part := roofs.pick_random() as BuildingPart
		_spawn_part(roof_part, current_height)


func _spawn_part(part: BuildingPart, y_offset: float) -> float:
	if not part or not part.scene:
		return 0.0

	var instance := part.scene.instantiate() as Node3D
	if not instance:
		return 0.0

	add_child(instance)
	instance.position.y = y_offset

	# Setting owner to the edited scene root ensures persistence in the .tscn file.
	var scene_root := get_tree().edited_scene_root if Engine.is_editor_hint() else owner
	if scene_root:
		instance.owner = scene_root

	return part.height


func _clear_children() -> void:
	for child in get_children():
		child.queue_free()
