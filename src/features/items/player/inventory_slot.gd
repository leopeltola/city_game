class_name InventorySlot
extends Panel
## A single hotbar slot: item icon, optional count/money label, slot-number hint,
## a selection highlight and small juice animations played by [ItemInventoryUI].
##
## Styles are derived from the active theme's panel style so the slot matches the
## rest of the UI, with a blue accent border when selected.

## Accent border of the selected slot
const COLOR_SELECTED_BORDER := Color(0.38, 0.643, 0.957, 1.0)
## Slightly blue-tinted background of the selected slot.
const COLOR_SELECTED_BG := Color(0.874, 0.9, 0.933)

@onready var _icon: TextureRect = %Icon
@onready var _count: Label = %Count
@onready var _index: Label = %Index

var _style_normal: StyleBoxFlat
var _style_selected: StyleBoxFlat
var _selected := false
var _tween: Tween
var _icon_tween: Tween


func _ready() -> void:
	_build_styles()
	set_selected(false)


# Derives the normal/selected styleboxes from the theme's panel style.
func _build_styles() -> void:
	var base := get_theme_stylebox("panel")
	if base is StyleBoxFlat:
		_style_normal = (base as StyleBoxFlat).duplicate() as StyleBoxFlat
	else:
		_style_normal = StyleBoxFlat.new()
		_style_normal.set_corner_radius_all(6)

	_style_normal.shadow_color = Color(0, 0, 0, 0.18)
	_style_normal.shadow_size = 3
	_style_normal.shadow_offset = Vector2(0, 2)

	_style_selected = _style_normal.duplicate() as StyleBoxFlat
	_style_selected.bg_color = COLOR_SELECTED_BG
	_style_selected.border_color = COLOR_SELECTED_BORDER
	_style_selected.set_border_width_all(2)
	_style_selected.shadow_color = Color(COLOR_SELECTED_BORDER, 0.35)
	_style_selected.shadow_size = 5

	add_theme_stylebox_override("panel", _style_normal)


## Sets the slot-number hint shown in the corner.
func set_index(value: int) -> void:
	_index.text = str(value)


## Updates the icon and optional count text. Pass [param icon] = null for an empty slot.
func set_slot(icon: Texture2D, count_text: String = "") -> void:
	_icon.texture = icon
	_icon.visible = icon != null
	set_count(count_text)


## Updates only the count/money label, leaving the icon and animations untouched.
func set_count(count_text: String) -> void:
	if count_text.is_empty():
		if _count.visible:
			_count.hide()
		return
	if _count.text != count_text:
		_count.text = count_text
	if not _count.visible:
		_count.show()


## Toggles the blue selected highlight. No-op when the state is unchanged.
func set_selected(value: bool) -> void:
	if value == _selected and has_theme_stylebox_override("panel"):
		return
	_selected = value
	add_theme_stylebox_override("panel", _style_selected if value else _style_normal)


## Plays the entrance pop when the hotbar first appears.
func play_in(delay: float = 0.0) -> void:
	prime_pivot()
	scale = Vector2(0.6, 0.6)
	modulate.a = 0.0
	_kill_tween()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, 0.16).set_delay(delay)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.3).set_delay(delay) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Plays the pop-in used when an item lands in this slot.
func play_add() -> void:
	_icon.pivot_offset = _icon.size * 0.5
	_icon.scale = Vector2(0.3, 0.3)
	_icon.rotation_degrees = -18.0
	_icon.modulate.a = 0.0
	_kill_icon_tween()
	_icon_tween = create_tween().set_parallel(true)
	_icon_tween.tween_property(_icon, "modulate:a", 1.0, 0.12)
	_icon_tween.tween_property(_icon, "scale", Vector2(1.18, 1.18), 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_icon_tween.tween_property(_icon, "rotation_degrees", 0.0, 0.28) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_icon_tween.chain().tween_property(_icon, "scale", Vector2.ONE, 0.1) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Plays the anticipation-then-snap-out used when an item leaves this slot.
func play_remove() -> void:
	_icon.pivot_offset = _icon.size * 0.5
	_count.hide()
	_kill_icon_tween()
	_icon_tween = create_tween()
	_icon_tween.tween_property(_icon, "scale", Vector2(1.15, 1.15), 0.08) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_icon_tween.tween_property(_icon, "scale", Vector2(0.3, 0.3), 0.16) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_icon_tween.parallel().tween_property(_icon, "rotation_degrees", 18.0, 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_icon_tween.parallel().tween_property(_icon, "modulate:a", 0.0, 0.14)
	_icon_tween.tween_callback(_clear_icon)


## Plays the selection pop when this slot becomes the active one.
func play_select() -> void:
	prime_pivot()
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2(1.12, 1.12), 0.08) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.16) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Recomputes the pivot used for scale tweens. Safe to call before animating.
func prime_pivot() -> void:
	pivot_offset = size * 0.5


func _clear_icon() -> void:
	_icon.texture = null
	_icon.visible = false
	_icon.scale = Vector2.ONE
	_icon.rotation_degrees = 0.0
	_icon.modulate.a = 1.0


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()


func _kill_icon_tween() -> void:
	if _icon_tween and _icon_tween.is_valid():
		_icon_tween.kill()
