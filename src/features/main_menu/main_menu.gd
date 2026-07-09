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
