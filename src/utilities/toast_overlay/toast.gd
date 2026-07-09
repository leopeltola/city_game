extends Control

@export var text: String = "PLACEHOLDER":
	set(val):
		text = val
		%Label.text = text
@export var time_s: int = 5

var _watch: Stopwatch
var _exiting := false

func _ready() -> void:
	%Label.text = text
	slide_in()
	_watch = Stopwatch.new()


func _process(_delta: float) -> void:
	if not _exiting and _watch.measure() > time_s * 1000:
		_exiting = true
		await slide_out()
		queue_free()


func slide_in() -> void:
	$MarginContainer.position = Vector2(0, -8)
	$MarginContainer.modulate = Color.TRANSPARENT
	var tween := create_tween().set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property($MarginContainer, "modulate", Color.WHITE, .5)
	tween.parallel().tween_property($MarginContainer, "position", Vector2(), .5)
	await tween.finished


func slide_out() -> void:
	var tween := create_tween().set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property($MarginContainer, "position", Vector2(10, 0), .5)
	tween.parallel().tween_property($MarginContainer, "modulate", Color.TRANSPARENT, .5)
	await tween.finished
