@tool
extends RefCounted
## Generates a prop item's data files from the token templates in
## addons/game_editor_plugin/templates/:
##   <name>.tres         ItemType resource (with display_scene wired to the glb)
##   <name>_world.tscn   ItemWorld RigidBody3D scene
##   <name>_equip.tscn   PropEquip scene (HeldAnchor + WornVisual)
## It also registers the type in item_manager.gd's _item_types dictionary.
##
## generate() returns "" on success or a human-readable error message.

const TEMPLATE_DIR := "res://addons/game_editor_plugin/templates/"
const ITEM_MANAGER_SCRIPT := "res://src/features/items/item_manager.gd"
const REGISTRY_ANCHOR := "const _item_types: Dictionary[StringName, ItemType] = {"

const TOKEN_NAME := "__NAME__"
const TOKEN_PASCAL := "__PASCAL__"
const TOKEN_DISPLAY := "__DISPLAY__"
const TOKEN_SLOT := "__SLOT__"
const TOKEN_DIR := "__DIR__"
const TOKEN_GLB_PATH := "__GLB_PATH__"
const TOKEN_GLB_UID := "__GLB_UID__"

const TEMPLATE_ITEM_TYPE := "prop_template.tres"
const TEMPLATE_WORLD := "prop_template_world.tscn"
const TEMPLATE_EQUIP := "prop_template_equip.tscn"


## Returns "" on success, or an error message on failure.
static func generate(glb_path: String, name: String, slot: int) -> String:
	var name_error := _validate_name(name)
	if not name_error.is_empty():
		return name_error
	if slot <= PropSystem.PropSlot.NONE or slot >= PropSystem.PropSlot.COUNT:
		return "Invalid prop slot."

	var dir := glb_path.get_base_dir()
	var item_type_path := dir.path_join(name + ".tres")
	var world_path := dir.path_join(name + "_world.tscn")
	var equip_path := dir.path_join(name + "_equip.tscn")

	for path: String in [item_type_path, world_path, equip_path]:
		if FileAccess.file_exists(path):
			return "A file already exists at %s." % path

	if _registry_has_type(name):
		return "Item type '%s' is already registered in item_manager.gd." % name

	var replacements := {
		TOKEN_NAME: name,
		TOKEN_PASCAL: name.to_pascal_case(),
		TOKEN_DISPLAY: name.capitalize(),
		TOKEN_SLOT: str(slot),
		TOKEN_DIR: dir,
		TOKEN_GLB_PATH: glb_path,
		TOKEN_GLB_UID: _read_glb_uid(glb_path),
	}

	var outputs := {
		TEMPLATE_ITEM_TYPE: item_type_path,
		TEMPLATE_WORLD: world_path,
		TEMPLATE_EQUIP: equip_path,
	}
	for template_name: String in outputs:
		var template := _read_file(TEMPLATE_DIR + template_name)
		if template.is_empty():
			return "Could not read template: %s" % (TEMPLATE_DIR + template_name)
		var error := _write_file(outputs[template_name], _apply_tokens(template, replacements))
		if not error.is_empty():
			return error

	return _register_type(name, item_type_path)


static func _validate_name(name: String) -> String:
	var regex := RegEx.new()
	regex.compile("^[a-z][a-z0-9_]*$")
	if regex.search(name) == null:
		return "Invalid name '%s'. Use lowercase snake_case (e.g. police_hat)." % name
	return ""


static func _apply_tokens(content: String, replacements: Dictionary) -> String:
	for token: String in replacements:
		content = content.replace(token, str(replacements[token]))
	# The glb may not expose a uid; drop the now-empty attribute entirely.
	return content.replace("uid=\"\"", "")


static func _read_glb_uid(glb_path: String) -> String:
	var import_path := glb_path + ".import"
	var content := _read_file(import_path)
	if content.is_empty():
		return ""
	var regex := RegEx.new()
	regex.compile("uid=\"(uid://[^\"]+)\"")
	var result := regex.search(content)
	if result == null:
		return ""
	return result.get_string(1)


static func _registry_has_type(type_name: String) -> bool:
	var content := _read_file(ITEM_MANAGER_SCRIPT)
	return content.contains("\"%s\":" % type_name)


static func _register_type(type_name: String, item_type_path: String) -> String:
	var content := _read_file(ITEM_MANAGER_SCRIPT)
	if content.is_empty():
		return "Could not read %s." % ITEM_MANAGER_SCRIPT

	var anchor := content.find(REGISTRY_ANCHOR)
	if anchor == -1:
		return "Could not find the _item_types registry in item_manager.gd."
	var insert_at := content.find("\n", anchor)
	if insert_at == -1:
		return "Malformed _item_types registry in item_manager.gd."
	insert_at += 1

	var entry := "\t\"%s\": preload(\"%s\"),\n" % [type_name, item_type_path]
	content = content.substr(0, insert_at) + entry + content.substr(insert_at)
	return _write_file(ITEM_MANAGER_SCRIPT, content)


static func _read_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var content := file.get_as_text()
	file.close()
	return content


static func _write_file(path: String, content: String) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Could not write %s (error %d)." % [path, FileAccess.get_open_error()]
	file.store_string(content)
	file.close()
	return ""
