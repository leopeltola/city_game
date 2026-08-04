@tool
extends EditorPlugin

var context_menu_script := preload("res://addons/template_directories/context_menu.gd")
var context_menu_plugin: EditorContextMenuPlugin
var dialog: ConfirmationDialog
var name_input: LineEdit
var current_template_path: String

func _enter_tree() -> void:
	context_menu_plugin = context_menu_script.new()
	context_menu_plugin.template_selected.connect(_on_template_selected)
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM, context_menu_plugin)
	_setup_dialog()

func _exit_tree() -> void:
	if context_menu_plugin:
		remove_context_menu_plugin(context_menu_plugin)
		context_menu_plugin = null
	if dialog:
		dialog.queue_free()

func _setup_dialog() -> void:
	dialog = ConfirmationDialog.new()
	dialog.title = "Create Item From Template"
	dialog.min_size = Vector2i(350, 100)
	
	var vbox = VBoxContainer.new()
	var label = Label.new()
	label.text = "Enter new item name:"
	vbox.add_child(label)
	
	name_input = LineEdit.new()
	vbox.add_child(name_input)
	
	dialog.add_child(vbox)
	dialog.register_text_enter(name_input)
	dialog.confirmed.connect(_on_dialog_confirmed)
	
	EditorInterface.get_base_control().add_child(dialog)

func _on_template_selected(path: String) -> void:
	current_template_path = path
	name_input.text = ""
	dialog.popup_centered()
	name_input.grab_focus()

func _on_dialog_confirmed() -> void:
	var new_name = name_input.text.strip_edges().to_lower()
	if new_name.is_empty() or not new_name.is_valid_filename():
		return
		
	var parent_dir = current_template_path.get_base_dir()
	var new_dir_path = parent_dir.path_join(new_name)
	
	if DirAccess.dir_exists_absolute(new_dir_path) or DirAccess.make_dir_absolute(new_dir_path) != OK:
		return
		
	_duplicate_template(current_template_path, new_dir_path, new_name)
	EditorInterface.get_resource_filesystem().scan()

func _duplicate_template(src_dir: String, dest_dir: String, new_name: String) -> void:
	var dir = DirAccess.open(src_dir)
	if not dir:
		return
		
	var uid_regex = RegEx.new()
	uid_regex.compile("uid=\"[^\"]*\"\\s*")
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir() and not file_name.ends_with(".uid"):
			var old_file_path = src_dir.path_join(file_name)
			var new_file_name = file_name.replace("template", new_name)
			var new_file_path = dest_dir.path_join(new_file_name)
			
			var file = FileAccess.open(old_file_path, FileAccess.READ)
			if file:
				var content = file.get_as_text()
				file.close()
				
				content = content.replace("template", new_name)
				content = uid_regex.sub(content, "", true)
				
				var new_file = FileAccess.open(new_file_path, FileAccess.WRITE)
				if new_file:
					new_file.store_string(content)
					new_file.close()
					
		file_name = dir.get_next()
