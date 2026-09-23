extends Control
## HUD element displaying the local player's crime status with expressive scale and fade
## animations. A bounty is shown prominently when the player is wanted; guilt is demoted
## to a smaller, dimmer secondary element while a bounty is visible.

## Alpha applied to the guilt label while a bounty is shown.
const DIM_ALPHA := 0.6

## Font size of the guilt label while a bounty is shown.
const DIM_FONT_SIZE := 16

## Outline size of the guilt label while a bounty is shown.
const DIM_OUTLINE_SIZE := 5

@onready var guilt_label: Label = %GuiltLabel
@onready var bounty_label: Label = %BountyLabel

var _current_guilt: int = 0
var _current_bounty: int = 0
var _is_shown: bool = false
var _tween: Tween
var _guilt_settings_normal: LabelSettings
var _guilt_settings_dim: LabelSettings


func _ready() -> void:
	resized.connect(_update_pivot)
	_update_pivot()

	_guilt_settings_normal = guilt_label.label_settings
	_guilt_settings_dim = guilt_label.label_settings.duplicate() as LabelSettings
	_guilt_settings_dim.font_size = DIM_FONT_SIZE
	_guilt_settings_dim.outline_size = DIM_OUTLINE_SIZE
	_guilt_settings_dim.font_color = Color(_guilt_settings_dim.font_color, DIM_ALPHA)

	modulate.a = 0.0
	scale = Vector2.ZERO
	hide()

	CrimeManager.guilt_changed.connect(_on_guilt_changed)
	CrimeManager.bounty_changed.connect(_on_bounty_changed)

	var local_player: PlayerData = PlayerManager.get_local_player_or_null()
	if local_player != null:
		set_guilt(CrimeManager.get_guilt(local_player.player_id))
		set_bounty(CrimeManager.get_player_bounty(local_player.player_id))


## Updates the guilt value and refreshes the overlay.
func set_guilt(guilt: int) -> void:
	if guilt == _current_guilt:
		return
	_current_guilt = guilt
	_refresh()


## Updates the bounty value and refreshes the overlay.
func set_bounty(bounty: int) -> void:
	if bounty == _current_bounty:
		return
	_current_bounty = bounty
	_refresh()


func _on_guilt_changed(player_id: int, guilt: int) -> void:
	if not _is_local_player(player_id):
		return
	set_guilt(guilt)


func _on_bounty_changed(player_id: int, bounty: int) -> void:
	if not _is_local_player(player_id):
		return
	set_bounty(bounty)


func _is_local_player(player_id: int) -> bool:
	var local_player: PlayerData = PlayerManager.get_local_player_or_null()
	return local_player != null and local_player.player_id == player_id


## Applies the current guilt/bounty to the labels and runs the matching animation.
func _refresh() -> void:
	var has_bounty: bool = _current_bounty > 0
	var has_guilt: bool = _current_guilt > 0
	var should_show: bool = has_bounty or has_guilt

	bounty_label.visible = has_bounty
	guilt_label.visible = has_guilt
	guilt_label.label_settings = _guilt_settings_dim if has_bounty else _guilt_settings_normal
	guilt_label.text = "%s€" % _current_guilt
	bounty_label.text = "%s€" % _current_bounty

	if _tween:
		_tween.kill()
	_tween = create_tween()

	if !should_show:
		if _is_shown:
			_animate_hide()
			_is_shown = false
	elif !_is_shown:
		_animate_show()
		_is_shown = true
	else:
		_animate_punch()


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
