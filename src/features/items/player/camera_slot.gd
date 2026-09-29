extends Panel
## HUD slot for the always-available camera gear. Mirrors an inventory slot and
## shows the "C" shortcut plus the post-photo cooldown. A pure view of the local
## player's [EquipHost] cooldown state; nothing here is authoritative.

## Slightly transparent icon while the camera is on cooldown.
const COLOR_ICON_COOLDOWN := Color(1, 1, 1, 0.35)

@export var inv: PlayerInventory = null

@onready var _icon: TextureRect = %Icon
@onready var _cooldown_overlay: Control = %CooldownOverlay
@onready var _cooldown_label: Label = %CooldownLabel


func _ready() -> void:
	_build_style()
	%Index.text = "C"
	_set_cooldown(0.0)


func _process(_delta: float) -> void:
	if inv == null or not is_instance_valid(inv.player):
		return
	var equip := inv.player.equipment
	if equip == null:
		return
	_set_cooldown(equip.get_camera_cooldown_remaining())


# Shows the dimmed overlay and remaining seconds while cooling down, and restores
# the slot to full brightness when ready.
func _set_cooldown(remaining: float) -> void:
	var on_cd := remaining > 0.0
	if _cooldown_overlay.visible != on_cd:
		_cooldown_overlay.visible = on_cd
		_icon.modulate = COLOR_ICON_COOLDOWN if on_cd else Color.WHITE
	if on_cd:
		_cooldown_label.text = str(ceili(remaining))


# Derives the slot stylebox from the theme's panel style, matching the hotbar slots.
func _build_style() -> void:
	var base := get_theme_stylebox("panel")
	var style: StyleBoxFlat
	if base is StyleBoxFlat:
		style = (base as StyleBoxFlat).duplicate() as StyleBoxFlat
	else:
		style = StyleBoxFlat.new()
		style.set_corner_radius_all(6)

	style.shadow_color = Color(0, 0, 0, 0.18)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 2)
	add_theme_stylebox_override("panel", style)
