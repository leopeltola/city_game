@tool
extends Path3D
## Distributes and aligns instantiated 3D props along a Curve3D path in the editor.

enum Mode {
	GAP_BASED,
	COUNT_BASED,
}

enum Alignment {
	PATH,
	WORLD,
}

@export_group("Source")
## The scene to instantiate along the path.
@export var prop_scene: PackedScene:
	set(value):
		prop_scene = value
		_queue_generate()

@export_group("Distribution")
## Placement calculation mode: fixed distance intervals or fixed total count.
@export var mode: Mode = Mode.GAP_BASED:
	set(value):
		mode = value
		_queue_generate()

## Distance between instances along the path in GAP_BASED mode.
@export_range(0.01, 1000.0, 0.1, "or_greater") var gap: float = 2.0:
	set(value):
		gap = maxf(0.01, value)
		_queue_generate()

## Number of instances to distribute evenly in COUNT_BASED mode.
@export_range(1, 1000, 1, "or_greater") var count: int = 5:
	set(value):
		count = maxi(1, value)
		_queue_generate()

## Distance offset from the start of the curve.
@export_range(0.0, 1000.0, 0.1, "or_greater") var start_offset: float = 0.0:
	set(value):
		start_offset = maxf(0.0, value)
		_queue_generate()

## Distance reserved before the end of the curve.
@export_range(0.0, 1000.0, 0.1, "or_greater") var end_offset: float = 0.0:
	set(value):
		end_offset = maxf(0.0, value)
		_queue_generate()

@export_group("Transform")
## Determines whether orientation tracks curve tangents or remains world-aligned.
@export var alignment: Alignment = Alignment.PATH:
	set(value):
		alignment = value
		_queue_generate()

## Position offset applied locally to each instance.
@export var placement_offset: Vector3 = Vector3.ZERO:
	set(value):
		placement_offset = value
		_queue_generate()

## Base rotation offset in degrees applied to each instance.
@export var rotation_offset: Vector3 = Vector3.ZERO:
	set(value):
		rotation_offset = value
		_queue_generate()

@export_group("Randomization")
## Deterministic seed for reproducible variations.
@export var random_seed: int = 0:
	set(value):
		random_seed = value
		_queue_generate()

## Maximum random rotation variation (+/- degrees per axis).
@export var random_rotation: Vector3 = Vector3.ZERO:
	set(value):
		random_rotation = value
		_queue_generate()

## Maximum uniform scale variation (+/- fraction, e.g., 0.2 = 80% to 120%).
@export_range(0.0, 1.0, 0.05) var random_scale: float = 0.0:
	set(value):
		random_scale = clampf(value, 0.0, 1.0)
		_queue_generate()

@export_group("Actions")
## Safety limit to avoid freezes when gap values are set too small.
@export_range(10, 5000, 10) var max_instances: int = 1000

## Inspector trigger to rebuild props on demand.
@export var regenerate: bool = false:
	set(value):
		if value:
			generate()

var _update_queued: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		curve_changed.connect(_queue_generate)


## Clears and regenerates all prop instances along the path.
func generate() -> void:
	_update_queued = false
	clear_props()

	if prop_scene == null or curve == null:
		return

	var length: float = curve.get_baked_length()
	var usable_length: float = length - start_offset - end_offset
	if usable_length <= 0.0:
		return

	var offsets: Array[float] = _calculate_offsets(usable_length)
	if offsets.is_empty():
		return

	var scene_root: Node = get_tree().edited_scene_root if (Engine.is_editor_hint() and get_tree()) else owner
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = random_seed

	for path_offset in offsets:
		var sample_distance: float = start_offset + path_offset
		var instance: Node3D = prop_scene.instantiate() as Node3D
		if instance == null:
			continue

		instance.set_meta(&"_prop_path_instance", true)
		instance.transform = _calculate_transform(sample_distance, rng)

		# force_readable_name = true gives readable, incremented names (e.g. Prop, Prop2)
		add_child(instance, true)

		# Assigning owner ensures nodes are saved within the scene file
		if scene_root:
			instance.owner = scene_root


## Deletes all previously instantiated prop instances.
func clear_props() -> void:
	for child in get_children():
		if child.has_meta(&"_prop_path_instance"):
			child.free()


func _queue_generate() -> void:
	if not is_inside_tree() or not Engine.is_editor_hint():
		return
	if _update_queued:
		return
	_update_queued = true
	generate.call_deferred()


func _calculate_offsets(usable_length: float) -> Array[float]:
	var offsets: Array[float] = []
	match mode:
		Mode.GAP_BASED:
			var current: float = 0.0
			var counter: int = 0
			while current <= usable_length and counter < max_instances:
				offsets.append(current)
				current += gap
				counter += 1
		Mode.COUNT_BASED:
			if count == 1:
				offsets.append(usable_length * 0.5)
			else:
				var step: float = usable_length / float(count - 1)
				for i in range(mini(count, max_instances)):
					offsets.append(i * step)
	return offsets


func _calculate_transform(offset: float, rng: RandomNumberGenerator) -> Transform3D:
	var base_xform: Transform3D
	match alignment:
		Alignment.PATH:
			base_xform = curve.sample_baked_with_rotation(offset, false, true)
		Alignment.WORLD:
			base_xform = Transform3D(Basis.IDENTITY, curve.sample_baked(offset))

	var rad_offset: Vector3 = Vector3(
		deg_to_rad(rotation_offset.x),
		deg_to_rad(rotation_offset.y),
		deg_to_rad(rotation_offset.z),
	)

	if random_rotation != Vector3.ZERO:
		rad_offset += Vector3(
			deg_to_rad(rng.randf_range(-random_rotation.x, random_rotation.x)),
			deg_to_rad(rng.randf_range(-random_rotation.y, random_rotation.y)),
			deg_to_rad(rng.randf_range(-random_rotation.z, random_rotation.z)),
		)

	var local_xform: Transform3D = Transform3D(Basis.from_euler(rad_offset), placement_offset)
	var final_xform: Transform3D = base_xform * local_xform

	if random_scale > 0.0:
		var s: float = rng.randf_range(1.0 - random_scale, 1.0 + random_scale)
		final_xform = final_xform.scaled_local(Vector3(s, s, s))

	return final_xform
