@tool
extends Node3D

const RoadMarking = preload("res://src/features/city/ground/road_marking.gd")

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
## Road marking module spawned along lane center lines.
@export var road_marking: PackedScene

## Black and white layout mask where each 3x3 pixel block corresponds to 1 tile module.
@export var layout_texture: Texture2D
## World space dimension of each tile square in meters.
@export var tile_size: float = 10.0

@export_group("Markings")
## Generate lane markings along the roads.
@export var generate_markings: bool = true
## Style of the dashed lane center line.
@export var center_line_type: RoadMarking.Type = RoadMarking.Type.WHITE_STRIPE
## Width of the center line in meters.
@export var center_line_width: float = 0.2
## Style of the intersection stop lines.
@export var stop_line_type: RoadMarking.Type = RoadMarking.Type.WHITE_FULL
## Width of the stop lines in meters.
@export var stop_line_width: float = 0.4
## Vertical offset of markings from the road surface.
@export var marking_height: float = 0.01
## Tangent length of turn curves in meters. ~2.76 approximates a quarter circle.
@export var turn_handle: float = 2.76
## Half width of a lane, used to size stop lines.
@export var road_half_width: float = 3.3

## Triggers generation from the inspector.
@export_tool_button("Generate Roads", "NavigationRegion3D") var generate_action: Callable = generate_roads

const MASK_NORTH: int = 1
const MASK_EAST: int = 2
const MASK_SOUTH: int = 4
const MASK_WEST: int = 8

# Indexed North, East, South, West.
const DIR_VECTORS := [
	Vector3i(0, 0, -1),
	Vector3i(1, 0, 0),
	Vector3i(0, 0, 1),
	Vector3i(-1, 0, 0),
]
const DIR_MASKS := [MASK_NORTH, MASK_EAST, MASK_SOUTH, MASK_WEST]
const TURN_MASKS := [3, 6, 9, 12]


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
	var masks := {}

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

			if mask != 0:
				masks[Vector2i(tx, tz)] = mask

	if generate_markings and road_marking:
		_generate_markings(masks)


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
	_assign_owner(instance)


func _clear_children() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


## Traces lane center lines between terminals (junctions and dead ends) and
## adds stop lines on the incoming half of every junction arm.
func _generate_markings(masks: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "RoadMarkings"
	add_child(root, true)
	_assign_owner(root)

	var visited := {}

	# Runs that start and end at a junction or dead end.
	for tile: Vector2i in masks:
		var mask: int = masks[tile]
		if _popcount(mask) == 2:
			continue
		for dir_index in 4:
			if not (mask & DIR_MASKS[dir_index]):
				continue
			var neighbor: Vector2i = tile + _grid_step(dir_index)
			if not masks.has(neighbor) or _popcount(masks[neighbor]) != 2:
				continue
			if visited.has(neighbor):
				continue
			_trace_run(neighbor, dir_index, masks, visited, root)

	# Closed loops with no terminal at all.
	for tile: Vector2i in masks:
		if _popcount(masks[tile]) == 2 and not visited.has(tile):
			var mask: int = masks[tile]
			for dir_index in 4:
				if mask & DIR_MASKS[dir_index]:
					# Travel into the tile from this connected side.
					_trace_run(tile, (dir_index + 2) % 4, masks, visited, root)
					break

	# Stop lines on the incoming (right-hand) lane of every junction arm.
	for tile: Vector2i in masks:
		var count := _popcount(masks[tile])
		if count == 3 or count == 4:
			_spawn_stop_lines(tile, masks[tile], root)


## Walks from `first` through degree-2 tiles until the next terminal, curve
## closure, or already-visited tile, accumulating a single marking curve.
func _trace_run(first: Vector2i, entry_dir: int, masks: Dictionary, visited: Dictionary, root: Node3D) -> void:
	var half := tile_size * 0.5
	var curve := Curve3D.new()

	var current := first
	var dir := entry_dir
	curve.add_point(_tile_center(current) - _dir_vector(dir) * half)

	while true:
		visited[current] = true
		var mask: int = masks[current]
		var exit_dir := _other_direction(mask, dir)
		var exit_pos := _tile_center(current) + _dir_vector(exit_dir) * half

		if mask in TURN_MASKS:
			var entry_pos := _tile_center(current) - _dir_vector(dir) * half
			var entry_index := _ensure_point(curve, entry_pos)
			curve.set_point_out(entry_index, _dir_vector(dir) * turn_handle)
			var exit_index := _ensure_point(curve, exit_pos)
			curve.set_point_in(exit_index, -_dir_vector(exit_dir) * turn_handle)

		var next_tile: Vector2i = current + _grid_step(exit_dir)
		if not masks.has(next_tile) or _popcount(masks[next_tile]) != 2 or visited.has(next_tile):
			_ensure_point(curve, exit_pos)
			break

		current = next_tile
		dir = exit_dir

	_spawn_marking(curve, center_line_type, center_line_width, root)


func _spawn_stop_lines(tile: Vector2i, mask: int, root: Node3D) -> void:
	var half := tile_size * 0.5
	var center := _tile_center(tile)
	for dir_index in 4:
		if not (mask & DIR_MASKS[dir_index]):
			continue
		var outward := _dir_vector(dir_index)
		var heading := -outward
		var right := heading.cross(Vector3.UP).normalized()
		var edge := center + outward * half
		var curve := Curve3D.new()
		curve.add_point(edge)
		curve.add_point(edge + right * road_half_width)
		_spawn_marking(curve, stop_line_type, stop_line_width, root)


func _spawn_marking(curve: Curve3D, type: RoadMarking.Type, width: float, root: Node3D) -> void:
	if not road_marking:
		return
	var instance := road_marking.instantiate() as RoadMarking
	if not instance:
		return
	instance.name = "Marking_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 10000)
	root.add_child(instance, true)
	instance.position = Vector3(0.0, marking_height, 0.0)
	instance.curve = curve
	instance.type = type
	instance.width = width
	_assign_owner(instance)


func _ensure_point(curve: Curve3D, pos: Vector3) -> int:
	var last := curve.point_count - 1
	if last >= 0 and curve.get_point_position(last).is_equal_approx(pos):
		return last
	curve.add_point(pos)
	return curve.point_count - 1


func _other_direction(mask: int, entry_dir: int) -> int:
	var back := (entry_dir + 2) % 4
	for i in 4:
		if i != back and mask & DIR_MASKS[i]:
			return i
	return back


func _popcount(value: int) -> int:
	var count := 0
	while value > 0:
		count += value & 1
		value >>= 1
	return count


func _tile_center(tile: Vector2i) -> Vector3:
	return Vector3(tile.x * tile_size, 0.0, tile.y * tile_size)


func _dir_vector(dir_index: int) -> Vector3:
	return Vector3(DIR_VECTORS[dir_index])


func _grid_step(dir_index: int) -> Vector2i:
	var vec: Vector3i = DIR_VECTORS[dir_index]
	return Vector2i(vec.x, vec.z)


func _assign_owner(node: Node) -> void:
	var scene_root := get_tree().edited_scene_root if Engine.is_editor_hint() else owner
	if scene_root:
		node.owner = scene_root
