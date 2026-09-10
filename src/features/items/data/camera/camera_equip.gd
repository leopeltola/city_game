class_name CameraEquip
extends ItemEquip
## Camera gear toggled with the "camera" action (C). Not backed by a real item
## (is_unarmed()), so it is always available. PlayerInventory mounts/lowers it and
## restores the held slot item; getting hit lowers it too.
##
## While mounted, the rig idle comes from idle_animation_override ("camera_idle",
## set on the scene). LMB plays the "camera_take_shot" clip on every peer and calls
## _capture_photo() on the local player.

const TAKE_SHOT_ANIM := "camera_take_shot"
const TAKE_SHOT_START_BLEND := 0.1
const TAKE_SHOT_END_BLEND := 0.15

## True while a shot clip is playing, so LMB doesn't machine-gun the shutter.
var _busy := false
var _animator: PlayerAnimator = null


func _on_equipped() -> void:
	super()
	_busy = false


func _on_unequipped() -> void:
	super()
	_unhook_animator()
	_busy = false
	if is_instance_valid(player) and is_instance_valid(player.animator):
		player.animator.cancel_action(0.1)


func _unhandled_input(event: InputEvent) -> void:
	if not player.is_local or (HUD.instance and HUD.instance.is_blocking_input()):
		return
	if event.is_action_pressed("left_click"):
		_request_take_shot()
		get_viewport().set_input_as_handled()


func _request_take_shot() -> void:
	if _busy:
		return
	_rpc_take_shot.rpc()


## Plays the shutter clip on every peer. Photo capture runs only on the local player.
@rpc("any_peer", "call_local", "reliable")
func _rpc_take_shot() -> void:
	if _busy:
		return
	if not _hook_animator():
		return
	_busy = true
	player.animator.play_action(TAKE_SHOT_ANIM, TAKE_SHOT_START_BLEND, TAKE_SHOT_END_BLEND)
	if player.is_local:
		_capture_photo()


## Photo capture hook
func _capture_photo() -> void:
	await get_tree().create_timer(0.6).timeout
	print("Photo captured")
	%SubViewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await get_tree().process_frame
	%SubViewport.get_texture()


func _hook_animator() -> bool:
	if is_instance_valid(_animator):
		return true
	if not is_instance_valid(player) or not is_instance_valid(player.animator):
		return false
	_animator = player.animator
	_animator.action_finished.connect(_on_animator_action_finished)
	_animator.action_cancelled.connect(_on_animator_action_cancelled)
	return true


func _unhook_animator() -> void:
	if not is_instance_valid(_animator):
		return
	if _animator.action_finished.is_connected(_on_animator_action_finished):
		_animator.action_finished.disconnect(_on_animator_action_finished)
	if _animator.action_cancelled.is_connected(_on_animator_action_cancelled):
		_animator.action_cancelled.disconnect(_on_animator_action_cancelled)
	_animator = null


func _on_animator_action_finished(_anim_name: StringName) -> void:
	_busy = false


func _on_animator_action_cancelled(_anim_name: StringName) -> void:
	_busy = false
