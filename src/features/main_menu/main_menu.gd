extends Control

@onready var main_menu: VBoxContainer = %MainMenu
@onready var lobby_menu: MarginContainer = %LobbyMenu
@onready var create_lobby_menu: MarginContainer = %CreateLobbyMenu
@onready var lobby_screen: MarginContainer = %LobbyScreen


func _ready() -> void:
	%JoinButton.pressed.connect(_show_lobby_menu)
	%ServerButton.pressed.connect(_show_create_lobby_menu)
	%QuitButton.pressed.connect(_on_quit_pressed)

	lobby_menu.back_requested.connect(_show_main_menu)
	create_lobby_menu.back_requested.connect(_show_main_menu)
	lobby_screen.leave_requested.connect(_on_lobby_leave_requested)

	if Lobby.instance:
		Lobby.instance.lobby_joined.connect(_show_lobby_screen)
		Lobby.instance.lobby_failed.connect(_on_lobby_failed)

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
	lobby_screen.hide()


func _show_lobby_menu() -> void:
	main_menu.hide()
	create_lobby_menu.hide()
	lobby_screen.hide()
	lobby_menu.show()


func _show_create_lobby_menu() -> void:
	main_menu.hide()
	lobby_menu.hide()
	lobby_screen.hide()
	create_lobby_menu.show()


func _show_lobby_screen() -> void:
	main_menu.hide()
	lobby_menu.hide()
	create_lobby_menu.hide()
	lobby_screen.show()


func _on_lobby_leave_requested() -> void:
	if Lobby.instance:
		Lobby.instance.leave()
	_show_main_menu()


func _on_lobby_failed(reason: String) -> void:
	ToastOverlay.show_info(reason)
	if is_visible_in_tree():
		_show_main_menu()


func _on_quit_pressed() -> void:
	if Lobby.instance:
		Lobby.instance.leave()
	get_tree().quit()
