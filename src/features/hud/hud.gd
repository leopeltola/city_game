class_name HUD
extends Control

static var instance: HUD = null

const MoneyPrompt := preload("res://src/features/hud/prompts/money_prompt.gd")
const WelfarePrompt := preload("res://src/features/city/kela/application/welfare_prompt.gd")


func _ready() -> void:
	HUD.instance = self

	%MoneyPrompt.hide()
	%PersonalMenu.hide()


func _exit_tree() -> void:
	if HUD.instance == self:
		HUD.instance = null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_info"):
		print("open info pressed")
		toggle_personal_menu("info")
	elif event.is_action_pressed("open_messages"):
		toggle_personal_menu("messages")


func clear_menus() -> void:
	hide_personal_menu()


func queue_msg_toast(from: String, title: String, msg: String) -> void:
	$MessagesToast.queue_msg_toast(from, title, msg)


func open_personal_menu(tab: StringName = "info") -> void:
	if is_blocking_input():
		return
	%PersonalMenu.show()
	%PersonalMenu.set_tab(tab)


func toggle_personal_menu(tab: StringName = "info") -> void:
	if %PersonalMenu.visible:
		%PersonalMenu.hide()
		return
	else:
		open_personal_menu(tab)


func hide_personal_menu() -> void:
	%PersonalMenu.hide()


func prompt_money(max: int = 1_000_000, default: int = 0, title: String = "") -> MoneyPrompt.Result:
	return await %MoneyPrompt.prompt(max, default, title)


func prompt_welfare() -> WelfarePrompt.Result:
	return await %WelfarePrompt.prompt()


## Returns true while the money prompt is on screen.
func is_money_prompt_open() -> bool:
	return %MoneyPrompt.visible


## Returns true while the welfare prompt is on screen.
func is_welfare_prompt_open() -> bool:
	return %WelfarePrompt.visible


## Returns true while the personal menu is on screen.
func is_personal_menu_open() -> bool:
	return %PersonalMenu.visible


func show_interact_label(text: String) -> void:
	%InteractLabel.text = text
	%InteractLabel.show()
	%Crosshair.hide()


func hide_interact_label() -> void:
	%InteractLabel.hide()
	%Crosshair.show()


## Returns true if an active modal or overlay should block player gameplay inputs.
func is_blocking_input() -> bool:
	return is_money_prompt_open() or is_welfare_prompt_open()
