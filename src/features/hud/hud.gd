class_name HUD
extends Control

static var instance: HUD = null

const MoneyPrompt := preload("res://src/features/hud/prompts/money_prompt.gd")


func _ready() -> void:
	HUD.instance = self


func _exit_tree() -> void:
	if HUD.instance == self:
		HUD.instance = null


func prompt_money(max: int = 1_000_000) -> MoneyPrompt.Result:
	return await %MoneyPrompt.prompt(max)
