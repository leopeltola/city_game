@tool
extends EditorContextMenuPlugin

## Signals to the main plugin when a valid template directory is right-clicked.
signal template_selected(path: String)

func _popup_menu(paths: PackedStringArray) -> void:
	if paths.is_empty():
		return
		
	# Trim trailing slashes to guarantee get_file() accurately evaluates the folder name
	var path := paths[0].trim_suffix("/")
	
	if path.get_file() == "template" and DirAccess.dir_exists_absolute(path):
		# The callback must accept the PackedStringArray argument passed by the engine
		add_context_menu_item("Create using template...", _on_menu_item_selected.bind(path))

func _on_menu_item_selected(_paths: PackedStringArray, path: String) -> void:
	template_selected.emit(path)
