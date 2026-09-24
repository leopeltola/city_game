@tool
extends Node3D
## Editor-only "photo studio" that renders a flat-lit, transparent icon for every
## registered [ItemType] and saves it as `<item>_icon.png` next to that item's data.
##
## Open [code]icon_photographer.tscn[/code], tune the settings below, then press
## "Generate Icons" in the inspector. This tool never touches the item resources or
## the registry; it only writes PNGs, so icons still have to be assigned to
## [member ItemType.icon] by hand.
##
## Item types are read statically from [code]ItemManager[/code]'s `_item_types`
## registry, because autoloads are unavailable inside tool scripts. Rotation can be
## overridden per item with [member rotation_overrides].

const ITEM_MANAGER_SCRIPT := "res://src/features/items/item_manager.gd"
const REGISTRY_CONST := "_item_types"
const ICON_SUFFIX := "_icon.png"

## Size of the saved PNG. The render is fitted into this square, preserving aspect.
@export var output_size: Vector2i = Vector2i(256, 256):
	set(value):
		output_size = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		_apply_settings()
## Offscreen render resolution. Keep it >= [member output_size] for crisp results.
@export var render_size: Vector2i = Vector2i(512, 512):
	set(value):
		render_size = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		_apply_settings()
## Fraction of the item's bounds added as margin before fitting the camera.
@export_range(0.0, 1.0, 0.01) var padding: float = 0.08
## Rotation applied to items without a [member rotation_overrides] entry.
@export var default_rotation_degrees: Vector3 = Vector3(-15.0, -30.0, 0.0)
## Per item-type rotation, keyed by [member ItemType.name]. Overrides the default.
@export var rotation_overrides: Dictionary[StringName, Vector3] = { }
## When non-empty, only these item types are rendered.
@export var only_types: Array[StringName] = [ ]
## Flat ambient fill light energy.
@export_range(0.0, 4.0, 0.05) var ambient_energy: float = 0.7
## Directional key light energy; adds form and highlights for metallic materials.
@export_range(0.0, 4.0, 0.05) var key_light_energy: float = 0.8
## Direction the key light shines from.
@export var key_light_rotation_degrees: Vector3 = Vector3(-45.0, -30.0, 0.0)
@export_tool_button("Generate Icons") var generate_action: Callable = _generate_all

@onready var _viewport: SubViewport = %SubViewport
@onready var _world_environment: WorldEnvironment = %WorldEnvironment
@onready var _camera: Camera3D = %Camera3D
@onready var _key_light: DirectionalLight3D = %KeyLight
@onready var _pivot: Node3D = %Pivot

## Guards against overlapping runs if the button is pressed again mid-generation.
var _generating := false


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	_apply_settings()


## Pushes the current export values onto the studio rig.
func _apply_settings() -> void:
	if not is_inside_tree() or _viewport == null:
		return
	_viewport.size = render_size
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_key_light.rotation_degrees = key_light_rotation_degrees
	_key_light.light_energy = key_light_energy
	if _world_environment.environment:
		_world_environment.environment.ambient_light_energy = ambient_energy


## Renders and saves an icon for every discovered item type.
func _generate_all() -> void:
	if not Engine.is_editor_hint() or _generating:
		return
	_apply_settings()

	var item_types := _discover_item_types()
	if item_types.is_empty():
		push_warning("IconPhotographer: no item types found in %s." % ITEM_MANAGER_SCRIPT)
		return

	_generating = true
	var names: Array[String] = [ ]
	for key: StringName in item_types:
		if only_types.is_empty() or only_types.has(key):
			names.append(String(key))
	names.sort()

	var rendered := 0
	for type_name: String in names:
		var item_type: ItemType = item_types[StringName(type_name)]
		if await _render_item(item_type):
			rendered += 1

	_generating = false
	print("IconPhotographer: rendered %d/%d icons." % [rendered, names.size()])
	EditorInterface.get_resource_filesystem().scan()


## Returns the `_item_types` registry, read from the script constant map when
## possible and parsed from source otherwise.
func _discover_item_types() -> Dictionary:
	var script := load(ITEM_MANAGER_SCRIPT)
	if script is GDScript:
		var constants: Dictionary = (script as GDScript).get_script_constant_map()
		if constants.has(REGISTRY_CONST):
			var registry: Dictionary = constants[REGISTRY_CONST]
			if not registry.is_empty():
				return registry
	return _parse_registry()


## Fallback discovery: scrapes `"name": preload("path")` entries out of the source.
func _parse_registry() -> Dictionary:
	var result: Dictionary = { }
	var file := FileAccess.open(ITEM_MANAGER_SCRIPT, FileAccess.READ)
	if file == null:
		return result
	var text := file.get_as_text()
	file.close()

	var regex := RegEx.new()
	regex.compile("\"([a-z0-9_]+)\"\\s*:\\s*preload\\(\"([^\"]+)\"\\)")
	for entry: RegExMatch in regex.search_all(text):
		var item_type := load(entry.get_string(2)) as ItemType
		if item_type:
			result[StringName(entry.get_string(1))] = item_type
	return result


## Renders a single item. Returns true when a PNG was written.
func _render_item(item_type: ItemType) -> bool:
	var scene := _resolve_scene(item_type)
	if scene == null:
		push_warning("IconPhotographer: '%s' has no world or display scene; skipped." % item_type.name)
		return false

	var root := scene.instantiate()
	if not root is Node3D:
		push_warning("IconPhotographer: '%s' scene root is not a Node3D; skipped." % item_type.name)
		root.free()
		return false
	var instance := root as Node3D

	_pivot.add_child(instance)
	_hide_non_visuals(instance)
	instance.rotation_degrees = rotation_overrides.get(StringName(item_type.name), default_rotation_degrees)
	await get_tree().process_frame

	var merged: Variant = _merge_visible_mesh_aabbs(instance)
	if merged == null:
		push_warning("IconPhotographer: '%s' has no visible meshes; skipped." % item_type.name)
		instance.queue_free()
		return false
	var bounds: AABB = merged
	instance.position -= bounds.get_center()
	await get_tree().process_frame

	_fit_camera(bounds)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	instance.queue_free()

	if image == null or image.is_empty():
		push_warning("IconPhotographer: '%s' produced an empty render; skipped." % item_type.name)
		return false

	var used := image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		push_warning("IconPhotographer: '%s' rendered nothing visible; skipped." % item_type.name)
		return false

	var path := _icon_path(item_type)
	if path.is_empty():
		push_warning("IconPhotographer: '%s' has no resource path; skipped." % item_type.name)
		return false

	var error := _fit_to_square(image.get_region(used)).save_png(path)
	if error != OK:
		push_warning("IconPhotographer: could not save %s (error %d)." % [path, error])
		return false

	print("IconPhotographer: wrote %s" % path)
	return true


## Resolves an item's visual scene without calling ItemType methods, which are
## unavailable on placeholder resources in the editor (the script is not @tool).
func _resolve_scene(item_type: ItemType) -> PackedScene:
	if not item_type.world_item_path.is_empty():
		var world := load(item_type.world_item_path) as PackedScene
		if world:
			return world
	return item_type.display_scene


## Hides scene decorations that should not appear in an icon (debug labels).
func _hide_non_visuals(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Label3D:
			(node as Label3D).visible = false
		for child in node.get_children():
			stack.append(child)


## Returns the merged world-space [AABB] of every visible mesh under [param root],
## or null when there is nothing to render.
func _merge_visible_mesh_aabbs(root: Node) -> Variant:
	var found := false
	var bounds := AABB()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh != null and mesh_instance.is_visible_in_tree():
				var mesh_bounds := mesh_instance.global_transform * mesh_instance.get_aabb()
				bounds = mesh_bounds if not found else bounds.merge(mesh_bounds)
				found = true
		for child in node.get_children():
			stack.append(child)
	return bounds if found else null


## Points the orthographic camera at the origin so [param bounds] fits the view.
func _fit_camera(bounds: AABB) -> void:
	var aspect := float(render_size.x) / float(render_size.y)
	var required := maxf(bounds.size.y, bounds.size.x / aspect)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	_camera.size = maxf(required * (1.0 + padding), 0.001)
	_camera.near = 0.01
	_camera.far = bounds.size.z + 10.0
	_camera.position = Vector3(0.0, 0.0, bounds.size.z * 0.5 + 1.0)


## Fits a tightly cropped render onto a transparent [member output_size] square.
func _fit_to_square(cropped: Image) -> Image:
	var scale := minf(
			float(output_size.x) / float(cropped.get_width()),
			float(output_size.y) / float(cropped.get_height()))
	var fit_size := Vector2i(
			maxi(1, roundi(cropped.get_width() * scale)),
			maxi(1, roundi(cropped.get_height() * scale)))
	if fit_size != cropped.get_size():
		cropped.resize(fit_size.x, fit_size.y, Image.INTERPOLATE_LANCZOS)

	var canvas := Image.create(output_size.x, output_size.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0.0, 0.0, 0.0, 0.0))
	var destination := Vector2i((output_size.x - fit_size.x) / 2, (output_size.y - fit_size.y) / 2)
	canvas.blit_rect(cropped, Rect2i(Vector2i.ZERO, fit_size), destination)
	return canvas


## Output path: `<item dir>/<name>_icon.png`.
func _icon_path(item_type: ItemType) -> String:
	var dir := item_type.resource_path.get_base_dir()
	if dir.is_empty():
		return ""
	return dir.path_join(item_type.name + ICON_SUFFIX)
