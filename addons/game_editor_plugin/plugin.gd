@tool
extends EditorPlugin
## Game-specific editor tooling. Currently adds a "Generate Prop" context menu
## for GLB/GLTF files inside items/ folders; see prop_generator.gd.

const PROP_CONTEXT_MENU := preload("res://addons/game_editor_plugin/prop_context_menu.gd")
const PROP_GENERATOR := preload("res://addons/game_editor_plugin/prop_generator.gd")

var _context_menu_plugin: EditorContextMenuPlugin
var _dialog: ConfirmationDialog
var _name_input: LineEdit
var _error_dialog: AcceptDialog
var _pending_glb_path := ""
var _pending_slot := 0


func _enter_tree() -> void:
	_context_menu_plugin = PROP_CONTEXT_MENU.new()
	_context_menu_plugin.prop_requested.connect(_on_prop_requested)
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM, _context_menu_plugin)
	_setup_dialogs()


func _exit_tree() -> void:
	if _context_menu_plugin:
		remove_context_menu_plugin(_context_menu_plugin)
		_context_menu_plugin = null
	if _dialog:
		_dialog.queue_free()
		_dialog = null
	if _error_dialog:
		_error_dialog.queue_free()
		_error_dialog = null


func _setup_dialogs() -> void:
	var base := EditorInterface.get_base_control()

	_dialog = ConfirmationDialog.new()
	_dialog.title = "Generate Prop"
	_dialog.min_size = Vector2i(360, 110)
	var vbox := VBoxContainer.new()
	var label := Label.new()
	label.text = "Enter the new prop name (lowercase snake_case):"
	vbox.add_child(label)
	_name_input = LineEdit.new()
	_name_input.placeholder_text = "police_hat"
	vbox.add_child(_name_input)
	_dialog.add_child(vbox)
	_dialog.register_text_enter(_name_input)
	_dialog.confirmed.connect(_on_dialog_confirmed)
	base.add_child(_dialog)

	_error_dialog = AcceptDialog.new()
	_error_dialog.title = "Generate Prop Failed"
	base.add_child(_error_dialog)


func _on_prop_requested(glb_path: String, slot: int) -> void:
	_pending_glb_path = glb_path
	_pending_slot = slot
	_name_input.text = glb_path.get_file().get_basename()
	_dialog.popup_centered()
	_name_input.grab_focus()
	_name_input.select_all()


func _on_dialog_confirmed() -> void:
	if _pending_glb_path.is_empty():
		return
	var new_name := _name_input.text.strip_edges().to_lower()
	var error := PROP_GENERATOR.generate(_pending_glb_path, new_name, _pending_slot)
	if error.is_empty():
		EditorInterface.get_resource_filesystem().scan()
		_pending_glb_path = ""
		return

	# Keep the prompt open so the name can be corrected.
	_dialog.popup_centered()
	_name_input.grab_focus()
	_name_input.select_all()
	_error_dialog.dialog_text = error
	_error_dialog.popup_centered()
