@tool
extends Node3D

## 4-way intersection module.
@export var road_4_way: PackedScene
## 3-way T-junction module. Assumes base orientation connects West (-X), North (-Z), and East (+X).
@export var road_3_way: PackedScene
## Straight road module. Assumes base orientation connects North (-Z) and South (+Z).
@export var road_straight: PackedScene
## 90-degree corner module. Assumes base orientation connects North (-Z) and East (+X).
@export var road_turn: PackedScene
## Non-road ground/plaza module.
@export var plaza: PackedScene

## Black and white layout mask where each 3x3 pixel block corresponds to 1 tile module.
@export var layout_texture: Texture2D
## World space dimension of each tile square in meters.
@export var tile_size: float = 10.0

## Triggers generation from the inspector.
@export_tool_button("Generate Roads", "NavigationRegion3D") var generate_action: Callable = generate_roads

const MASK_NORTH: int = 1
const MASK_EAST: int = 2
const MASK_SOUTH: int = 4
const MASK_WEST: int = 8


## Clears previous instances and builds the grid according to layout_texture.
func generate_roads() -> void:
	if not layout_texture:
		return

	var img := layout_texture.get_image()
	if not img:
		return

	_clear_children()

	var tile_count_x := img.get_width() / 3
	var tile_count_z := img.get_height() / 3

	for tz in tile_count_z:
		for tx in tile_count_x:
			var px := tx * 3
			var pz := tz * 3
			var world_pos := Vector3(tx * tile_size, 0.0, tz * tile_size)

			# Center pixel defines whether road exists on this module.
			if img.get_pixel(px + 1, pz + 1).r <= 0.5:
				_spawn_tile(plaza, world_pos, 0.0)
				continue

			var mask := 0
			if img.get_pixel(px + 1, pz).r > 0.5:
				mask |= MASK_NORTH
			if img.get_pixel(px + 2, pz + 1).r > 0.5:
				mask |= MASK_EAST
			if img.get_pixel(px + 1, pz + 2).r > 0.5:
				mask |= MASK_SOUTH
			if img.get_pixel(px, pz + 1).r > 0.5:
				mask |= MASK_WEST

			_place_road(mask, world_pos)


func _place_road(mask: int, pos: Vector3) -> void:
	match mask:
		# 4-way junction
		15:
			_spawn_tile(road_4_way, pos, 0.0)

		# 3-way T-junctions
		11: # N + E + W (Stem points South)
			_spawn_tile(road_3_way, pos, 0.0)
		13: # W + N + S (Stem points East)
			_spawn_tile(road_3_way, pos, 90.0)
		14: # E + S + W (Stem points North)
			_spawn_tile(road_3_way, pos, 180.0)
		7: # N + E + S (Stem points West)
			_spawn_tile(road_3_way, pos, 270.0)

		# Turns
		3: # N + E
			_spawn_tile(road_turn, pos, 0.0)
		9: # W + N
			_spawn_tile(road_turn, pos, 90.0)
		12: # S + W
			_spawn_tile(road_turn, pos, 180.0)
		6: # E + S
			_spawn_tile(road_turn, pos, 270.0)

		# Straights and Dead-ends
		1, 4, 5: # North/South aligned
			_spawn_tile(road_straight, pos, 0.0)
		2, 8, 10: # East/West aligned
			_spawn_tile(road_straight, pos, 90.0)
		_:
			_spawn_tile(plaza, pos, 0.0)


func _spawn_tile(scene: PackedScene, pos: Vector3, rot_y_deg: float) -> void:
	if not scene:
		return
	var instance := scene.instantiate() as Node3D
	if not instance:
		return
	instance.name = "Tile_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 10000)
	add_child(instance, true)
	instance.position = pos
	instance.rotation_degrees.y = rot_y_deg

	var scene_root := get_tree().edited_scene_root if Engine.is_editor_hint() else owner
	if scene_root:
		instance.owner = scene_root


func _clear_children() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
