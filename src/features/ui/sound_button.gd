class_name SoundButton
extends Button
## A [Button] that plays a UI sound on hover and on press. UI feedback is local to this
## peer, so the sounds are never networked. Override the exported streams to customise a
## button; the defaults are the shared UI sfx.

const DEFAULT_HOVER_SFX: AudioStream = preload("res://src/features/ui/assets/sfx/hover.ogg")
const DEFAULT_CLICK_SFX: AudioStream = preload("res://src/features/ui/assets/sfx/accept.ogg")

const HOVER_VOLUME_DB := -22.0
const CLICK_VOLUME_DB := -10.0

@export var hover_sfx: AudioStream = null
@export var click_sfx: AudioStream = null


func _ready() -> void:
	if hover_sfx == null:
		hover_sfx = DEFAULT_HOVER_SFX
	if click_sfx == null:
		click_sfx = DEFAULT_CLICK_SFX
	mouse_entered.connect(_on_mouse_entered)
	pressed.connect(_on_pressed)


func _on_mouse_entered() -> void:
	if disabled or hover_sfx == null:
		return
	Audio.play_sfx(hover_sfx, HOVER_VOLUME_DB)


func _on_pressed() -> void:
	if click_sfx == null:
		return
	Audio.play_sfx(click_sfx, CLICK_VOLUME_DB)
