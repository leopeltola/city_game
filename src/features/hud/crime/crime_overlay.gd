extends Control
## HUD element displaying local crime guilt with expressive scale and fade animations.

@onready var guilt_label: Label = %GuiltLabel

var _current_guilt: int = 0
var _tween: Tween


func _ready() -> void:
	resized.connect(_update_pivot)
	_update_pivot()

	modulate.a = 0.0
	scale = Vector2.ZERO
	hide()

	CrimeManager.local_guilt_changed.connect(_on_local_guilt_changed)


## Updates the guilt value and runs expressive entry, exit, or value-change animations.
func set_guilt(guilt: int) -> void:
	if guilt == _current_guilt:
		return

	var was_visible: bool = _current_guilt > 0
	@warning_ignore("shadowed_variable_base_class")
	var is_visible: bool = guilt > 0
	_current_guilt = guilt

	if _tween:
		_tween.kill()
	_tween = create_tween()

	if !is_visible:
		_animate_hide()
	elif !was_visible:
		guilt_label.text = "%s€" % guilt
		_animate_show()
	else:
		guilt_label.text = "%s€" % guilt
		_animate_punch()


func _on_local_guilt_changed(guilt: int) -> void:
	set_guilt(guilt)


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _animate_show() -> void:
	_update_pivot()
	show()
	scale = Vector2(0.4, 0.4)
	modulate.a = 0.0

	_tween.set_parallel(true)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.35) \
			.set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 1.0, 0.2) \
			.set_trans(Tween.TRANS_CUBIC) \
			.set_ease(Tween.EASE_OUT)


func _animate_hide() -> void:
	_update_pivot()
	_tween.set_parallel(true)
	_tween.tween_property(self, "scale", Vector2(0.5, 0.5), 0.22) \
			.set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_IN)
	_tween.tween_property(self, "modulate:a", 0.0, 0.18) \
			.set_trans(Tween.TRANS_CUBIC) \
			.set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(hide)


func _animate_punch() -> void:
	_update_pivot()
	scale = Vector2(1.15, 1.15)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.35) \
			.set_trans(Tween.TRANS_ELASTIC) \
			.set_ease(Tween.EASE_OUT)
