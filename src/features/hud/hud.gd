class_name HUD
extends Control

static var instance: HUD = null

const MoneyPrompt := preload("res://src/features/hud/prompts/money_prompt.gd")


func _ready() -> void:
	HUD.instance = self

	%MoneyPrompt.hide()


func _exit_tree() -> void:
	if HUD.instance == self:
		HUD.instance = null


func prompt_money(max: int = 1_000_000, default: int = 0, title: String = "") -> MoneyPrompt.Result:
	print("Prompting for money '%s': max %s, default %s" % [title, max, default])
	return await %MoneyPrompt.prompt(max, default, title)


## Returns true while the money prompt is on screen.
func is_money_prompt_open() -> bool:
	return %MoneyPrompt.visible


func show_interact_label(text: String) -> void:
	%InteractLabel.text = text
	%InteractLabel.show()
	%Crosshair.hide()


func hide_interact_label() -> void:
	%InteractLabel.hide()
	%Crosshair.show()
	
