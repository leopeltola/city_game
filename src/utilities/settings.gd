extends Node

signal setting_changed(setting: String, new_value, old_value)

const FILE_PATH: StringName = "user://settings.config"

var settings_data: Dictionary = {} # String: int | String


func _ready() -> void:
	load_settings(FILE_PATH)


func save_settings(file_path: String) -> void:
	var cf := ConfigFile.new()
	
	for key in settings_data.keys():
		cf.set_value("Settings", key, settings_data[key])
	
	cf.save(file_path)


func load_settings(file_path: String) -> void:
	var _settings := {}
	var cf := ConfigFile.new()
	var err := cf.load(file_path)
	
	if err != OK:
		push_error("Could not load settings: %s" % file_path)
	
	for section in cf.get_sections():
		for key in cf.get_section_keys(section):
			_settings[key] = cf.get_value(section, key)
	
	settings_data = _settings


func set_setting(key: String, value) -> void:
	var old_value = settings_data.get(key, null)
	settings_data[key] = value
	setting_changed.emit(key, value, old_value)
	save_settings(FILE_PATH)


func get_setting(key: String, default: Variant = null) -> Variant:
	return settings_data.get(key, default)
