extends Control

## Result of a prompt interaction.
class Result:
	var cancelled := false
	var amount: int = 0


@onready var line_edit: LineEdit = %LineEdit
@onready var ok_button: Button = %OkButton
@onready var cancel_button: Button = %CancelButton

signal _resolved(result: Result)

var _regex := RegEx.create_from_string(r"\D")


func _ready() -> void:
	line_edit.text_changed.connect(_on_text_changed)
	line_edit.text_submitted.connect(func(_text: String) -> void: _try_submit())
	ok_button.pressed.connect(_try_submit)
	cancel_button.pressed.connect(_cancel)
	hidden.connect(_cancel)

	visibility_changed.connect(
		func():
			if visible:
				line_edit.grab_focus()
	)


## Awaits until player either cancels or inputs a valid amount (0+).
## Cancels any ongoing prompt before starting a new one.
func prompt(max: int) -> Result:
	if visible:
		_cancel()

	line_edit.text = ""
	show()
	line_edit.grab_focus()

	var res: Result = await _resolved
	hide()
	return res


func _on_text_changed(new_text: String) -> void:
	var stripped := _regex.sub(new_text, "", true)
	if stripped != new_text:
		var caret_pos := line_edit.caret_column - (new_text.length() - stripped.length())
		line_edit.text = stripped
		line_edit.caret_column = max(0, caret_pos)


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
