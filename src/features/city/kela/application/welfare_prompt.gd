extends MarginContainer

signal _resolved(result: Result)

## Duration of the pop-in played when the form appears.
const INTRO_TIME := 0.15

@onready var name_edit: LineEdit = %NameLineEdit
@onready var social_assistance_check: CheckBox = %SocialAssistanceCheckbox
@onready var unemployment_check: CheckBox = %UnemploymentCheckbox
@onready var disability_check: CheckBox = %DisabilityCheckbox
@onready var terms_check: CheckBox = %TermsCheckbox

@onready var cancel_button: Button = %CancelButton
@onready var send_button: Button = %SendButton


class Result:
	var player_name: String
	var chosen_benefits: Array[String]
	var terms_accepted: bool
	var cancelled: bool


	@warning_ignore("shadowed_variable")
	func _init(p_name: String, benefits: Array[String], terms: bool, cancelled: bool) -> void:
		self.player_name = p_name
		self.chosen_benefits = benefits
		self.terms_accepted = terms
		self.cancelled = cancelled


	func _to_string() -> String:
		return "WelfareResult pname: %s, benefits: %s, terms accepted: %s, cancelled: %s" % [player_name, chosen_benefits, terms_accepted, cancelled]


func _ready() -> void:
	cancel_button.pressed.connect(_cancel)
	send_button.pressed.connect(_send)
	visibility_changed.connect(
		func():
			if not visible:
				_cancel()
	)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_cancel()
		get_viewport().set_input_as_handled()


## Awaits until player either cancels or sends the application
## Cancels any ongoing prompt before starting a new one.
func prompt() -> Result:
	if visible:
		_cancel()

	name_edit.text = ""
	social_assistance_check.button_pressed = false
	unemployment_check.button_pressed = false
	disability_check.button_pressed = false
	terms_check.button_pressed = false

	show()
	_play_intro()
	var _prev_mouse_mode := Input.mouse_mode
	if _prev_mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var result: Result = await _resolved

	hide()
	Input.mouse_mode = _prev_mouse_mode
	return result


## Pops the form in from the screen center instead of snapping on.
func _play_intro() -> void:
	pivot_offset = size * 0.5
	scale = Vector2(0.9, 0.9)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE, INTRO_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _send() -> void:
	var benefits: Array[String]
	if social_assistance_check.button_pressed:
		benefits.append("social_assistance")
	if unemployment_check.button_pressed:
		benefits.append("unemployment")
	if disability_check.button_pressed:
		benefits.append("disability")
	_resolved.emit(Result.new(name_edit.text, benefits, terms_check.button_pressed, false))


func _cancel() -> void:
	_resolved.emit(Result.new(name_edit.text, [], terms_check.button_pressed, true))
