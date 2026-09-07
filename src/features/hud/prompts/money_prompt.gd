extends Control

## Result of a prompt interaction.
class Result:
	var cancelled := false
	var amount: int = 0

## Default label text shown when no custom title is passed to [method prompt].
const DEFAULT_TITLE := "Put in money"

@onready var label: Label = %Label
@onready var line_edit: LineEdit = %LineEdit
@onready var ok_button: Button = %OkButton
@onready var cancel_button: Button = %CancelButton

signal _resolved(result: Result)

var _regex := RegEx.create_from_string(r"\D")
var _max_amount: int = 0


func _ready() -> void:
	line_edit.gui_input.connect(_on_line_edit_gui_input)
	line_edit.text_changed.connect(_on_text_changed)
	line_edit.text_submitted.connect(func(_text: String) -> void: _try_submit())
	ok_button.pressed.connect(_try_submit)
	cancel_button.pressed.connect(_cancel)
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


## Awaits until player either cancels or inputs a valid amount (0+).
## Cancels any ongoing prompt before starting a new one.
## [title] overrides the prompt's label text when provided.
func prompt(max_val: int, default: int = 0, title: String = "") -> Result:
	if visible:
		_cancel()

	_max_amount = max_val
	label.text = title if not title.is_empty() else DEFAULT_TITLE
	line_edit.text = str(default) if default > 0 else ""

	var _prev_mouse_mode := Input.mouse_mode
	if _prev_mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().warp_mouse(ok_button.get_global_rect().get_center())
	show()
	line_edit.grab_focus()

	var res: Result = await _resolved
	hide()
	Input.mouse_mode = _prev_mouse_mode
	return res


func _on_text_changed(new_text: String) -> void:
	var stripped := _regex.sub(new_text, "", true)
	if stripped.is_empty():
		line_edit.text = ""
		return

	if stripped.to_int() > _max_amount:
		stripped = str(_max_amount)

	if stripped != new_text:
		var caret_pos := mini(line_edit.caret_column, stripped.length())
		line_edit.text = stripped
		line_edit.caret_column = caret_pos


func _try_submit() -> void:
	if line_edit.text.is_empty():
		return
	var res := Result.new()
	res.amount = line_edit.text.to_int()
	_resolved.emit(res)


func _cancel() -> void:
	if _resolved.get_connections().is_empty():
		return
	var res := Result.new()
	res.cancelled = true
	_resolved.emit(res)


func _on_line_edit_gui_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.is_pressed():
		return

	# Allow shortcuts (e.g., Ctrl+C, Ctrl+V, Ctrl+A) and navigational/control keys
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return
	if event.unicode == 0:
		return

	# Block non-digit characters from being inserted or replacing the selection
	var char_typed := char(event.unicode)
	if char_typed < "0" or char_typed > "9":
		line_edit.accept_event()
