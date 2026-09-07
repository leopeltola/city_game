extends Control

@onready var main_menu: VBoxContainer = %MainMenu
@onready var lobby_menu: MarginContainer = %LobbyMenu
@onready var create_lobby_menu: MarginContainer = %CreateLobbyMenu


func _ready() -> void:
	%JoinButton.pressed.connect(_show_lobby_menu)
	%ServerButton.pressed.connect(_show_create_lobby_menu)
	%QuitButton.pressed.connect(func(): get_tree().quit())

	lobby_menu.back_requested.connect(_show_main_menu)
	create_lobby_menu.back_requested.connect(_show_main_menu)
	
	%PlayerNameLineEdit.text = Settings.get_setting("player_name", "")
	%PlayerNameLineEdit.text_changed.connect(
		func(new_text):
			Settings.set_setting("player_name", new_text)
			var pd := PlayerManager.get_local_player_or_null()
			if pd:
				pd.set_own_name_to(new_text)
	)

	_show_main_menu()


func _show_main_menu() -> void:
	main_menu.show()
	lobby_menu.hide()
	create_lobby_menu.hide()


func _show_lobby_menu() -> void:
	main_menu.hide()
	create_lobby_menu.hide()
	lobby_menu.show()


func _show_create_lobby_menu() -> void:
	main_menu.hide()
	lobby_menu.hide()
	create_lobby_menu.show()
