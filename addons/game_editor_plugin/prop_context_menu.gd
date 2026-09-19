@tool
extends EditorContextMenuPlugin
## Adds a "Generate Prop" submenu when a GLB/GLTF inside an items/ folder is
## right-clicked in the FileSystem dock. Emits prop_requested for the chosen
## PropSystem.PropSlot so the main plugin can prompt for a name and generate.

signal prop_requested(glb_path: String, slot: int)

const SLOTS: Array = [
	{ "label": "Torso", "slot": PropSystem.PropSlot.TORSO },
	{ "label": "Hat", "slot": PropSystem.PropSlot.HAT },
	{ "label": "Beard", "slot": PropSystem.PropSlot.BEARD },
	{ "label": "Glasses", "slot": PropSystem.PropSlot.GLASSES },
	{ "label": "Hand", "slot": PropSystem.PropSlot.HAND },
]

var _items_path_regex: RegEx


func _init() -> void:
	_items_path_regex = RegEx.new()
	_items_path_regex.compile("res://.*/items/.*\\.(glb|gltf)$")


func _popup_menu(paths: PackedStringArray) -> void:
	if paths.size() != 1:
		return
	var glb_path := paths[0].replace("\\", "/")
	if _items_path_regex.search(glb_path) == null:
		return

	var submenu := PopupMenu.new()
	for i in SLOTS.size():
		submenu.add_item(SLOTS[i]["label"], i)
	submenu.id_pressed.connect(_on_slot_selected.bind(glb_path))

	add_context_submenu_item("Generate Prop", submenu)


func _on_slot_selected(id: int, glb_path: String) -> void:
	prop_requested.emit(glb_path, SLOTS[id]["slot"])
