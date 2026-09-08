class_name HUD
extends Control

static var instance: HUD = null

const MoneyPrompt := preload("res://src/features/hud/prompts/money_prompt.gd")
const WelfarePrompt := preload("res://src/features/city/kela/application/welfare_prompt.gd")

var _stamina_tween: Tween


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


## Sets stamina bar value in the 0-1 range with juice for chunk costs and exhaustion.
func set_stamina(value: float) -> void:
	var target := clampf(value, 0.0, 1.0)
	var delta: float = target - %StaminaBar.value
	var was_depleted := is_zero_approx(%StaminaBar.value)

	%StaminaBar.value = target

	# Discrete chunk cost (e.g. ability or heavy action dropped > 5% in one tick)
	if delta < -0.05:
		punch_stamina(Vector2(1.25, 0.75))
	# Exhaustion pop when reaching 0
	elif is_zero_approx(target) and not was_depleted:
		punch_stamina(Vector2(0.75, 1.3), 8.0)


## Triggers an elastic squash/stretch and optional tilt on the stamina bar.
func punch_stamina(punch_scale: Vector2 = Vector2(1.25, 0.75), shake_deg: float = 0.0) -> void:
	var bar: Control = %StaminaBar
	bar.pivot_offset = bar.size * 0.5

	if _stamina_tween:
		_stamina_tween.kill()

	bar.scale = punch_scale
	if shake_deg > 0.0:
		bar.rotation_degrees = randf_range(-shake_deg, shake_deg)

	_stamina_tween = create_tween().set_parallel(true)
	_stamina_tween.tween_property(bar, "scale", Vector2.ONE, 0.4) \
			.set_trans(Tween.TRANS_ELASTIC) \
			.set_ease(Tween.EASE_OUT)

	if shake_deg > 0.0:
		_stamina_tween.tween_property(bar, "rotation_degrees", 0.0, 0.35) \
				.set_trans(Tween.TRANS_ELASTIC) \
				.set_ease(Tween.EASE_OUT)


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


@warning_ignore("shadowed_global_identifier")
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
