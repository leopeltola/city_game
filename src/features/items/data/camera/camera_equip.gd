class_name CameraEquip
extends ItemEquip
## Camera gear toggled with the "camera" action (C). Not backed by a real item
## (is_unarmed()), so it is always available. PlayerInventory mounts/lowers it and
## restores the held slot item; getting hit lowers it too.
##
## While mounted, the rig idle comes from idle_animation_override ("camera_idle",
## set on the scene). LMB plays the "camera_take_shot" clip on every peer and, on
## the local player, captures the SubViewport after a short delay, streams the image
## to every peer via ImageManager, and has a photo item placed in hand.

const TAKE_SHOT_ANIM := "camera_take_shot"
const TAKE_SHOT_START_BLEND := 0.1
const TAKE_SHOT_END_BLEND := 0.15
const CAPTURE_DELAY := 1.0

## Beyond this distance (m) a player scores nothing from the distance factor.
const MAX_IDENT_DISTANCE := 15.0
## Collision layers tested by identifiability raycasts: environment + player.
const RAY_MASK := 1 | 2
## Body points sampled per player, weighted by how much they carry identity.
const BODY_SAMPLES: Array[Dictionary] = [
	{ "offset": Vector3(0.0, 1.65, 0.0), "weight": 3.0 }, # head
	{ "offset": Vector3(0.0, 1.25, 0.0), "weight": 2.0 }, # chest
	{ "offset": Vector3(0.0, 0.85, 0.0), "weight": 1.0 }, # hips
]

## True while a shot clip is playing, so LMB doesn't machine-gun the shutter.
var _busy := false
## True from the shot until the captured photo item is in hand; gates further shots.
var _capturing := false
var _animator: PlayerAnimator = null

@onready var _photo_camera: Camera3D = %SubViewport/Camera3D


func _on_equipped() -> void:
	super()
	_busy = false
	_capturing = false


func _on_unequipped() -> void:
	super()
	_capturing = false
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
	if _busy or _capturing:
		return
	_rpc_take_shot.rpc()


## Plays the shutter clip on every peer. Capture runs only on the local player.
@rpc("any_peer", "call_local", "reliable")
func _rpc_take_shot() -> void:
	if _busy:
		return
	if not _hook_animator():
		return
	_busy = true
	player.animator.play_action(TAKE_SHOT_ANIM, TAKE_SHOT_START_BLEND, TAKE_SHOT_END_BLEND)
	if player.is_local:
		_capturing = true
		_capture_photo()


## Waits for the shutter to settle, grabs the SubViewport frame, and turns it into
## a photo item in hand. Aborts if the camera is lowered mid-capture.
func _capture_photo() -> void:
	await get_tree().create_timer(CAPTURE_DELAY).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	%SubViewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(self) or not is_inside_tree():
		return
	var img: Image = %SubViewport.get_texture().get_image()
	%SubViewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if img == null or img.is_empty():
		_capturing = false
		return
	var webp := img.save_webp_to_buffer()
	if webp.is_empty():
		_capturing = false
		return
	_request_photo_item(webp, _photographed_player())


func _request_photo_item(webp: PackedByteArray, subject: Dictionary) -> void:
	var photo_id := ImageManager.register_image(webp)
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_rpc_request_photo_item.rpc(photo_id, subject.player_id, subject.identifiability)
	else:
		_create_photo_item_local(photo_id, subject.player_id, subject.identifiability)


## Finds the player this photo best identifies: the in-frustum candidate with the
## highest score from body raycasts and distance. Returns { player_id, identifiability }
## with player_id 0 when nobody is clearly captured.
func _photographed_player() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var origin := _photo_camera.global_position
	var best := { "player_id": 0, "identifiability": 0 }

	for target: Player in PlayerManager.get_player_nodes():
		if target == player or not is_instance_valid(target):
			continue
		var chest: Vector3 = target.global_position + Vector3(0.0, 1.25, 0.0)
		if not _photo_camera.is_position_in_frustum(chest):
			continue

		var visible_weight := 0.0
		var total_weight := 0.0
		for sample: Dictionary in BODY_SAMPLES:
			total_weight += sample.weight
			if _sample_visible(space, origin, target, target.global_position + sample.offset):
				visible_weight += sample.weight

		var distance_factor := clampf(1.0 - origin.distance_to(chest) / MAX_IDENT_DISTANCE, 0.0, 1.0)
		var identifiability := int(roundf(100.0 * visible_weight / total_weight * distance_factor))
		if identifiability > best.identifiability:
			best = { "player_id": target.player_id, "identifiability": identifiability }

	return best


## True when a ray from the camera reaches [target_point] on [target] without being
## blocked by the environment or another body.
func _sample_visible(space: PhysicsDirectSpaceState3D, origin: Vector3, target: Player, target_point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(origin, target_point, RAY_MASK)
	query.exclude = [player.get_rid()]
	var hit := space.intersect_ray(query)
	return not hit.is_empty() and hit["collider"] == target


## Server-only: creates the photo item for the requesting client and returns its id.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_photo_item(photo_id: int, subject_player_id: int, identifiability: int) -> void:
	if not multiplayer.is_server():
		return
	if not ImageManager.has_image(photo_id):
		return
	var item_id = ItemManager.create_item_of_type("photo", {
		&"photo_id": photo_id,
		&"subject_player_id": subject_player_id,
		&"guilt": CrimeManager.get_guilt(subject_player_id),
		&"identifiability": identifiability,
	})
	if item_id == null:
		return
	_rpc_photo_item_created.rpc_id(multiplayer.get_remote_sender_id(), item_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_photo_item_created(item_id: int) -> void:
	if not player.is_local:
		return
	_capturing = false
	_give_photo_item(item_id)


func _create_photo_item_local(photo_id: int, subject_player_id: int, identifiability: int) -> void:
	_capturing = false
	var item_id = ItemManager.create_item_of_type("photo", {
		&"photo_id": photo_id,
		&"subject_player_id": subject_player_id,
		&"guilt": CrimeManager.get_guilt(subject_player_id),
		&"identifiability": identifiability,
	})
	if item_id != null:
		_give_photo_item(item_id)


## Equips the photo in the active slot, or drops it as a world item when the
## inventory is full.
func _give_photo_item(item_id: int) -> void:
	if not is_instance_valid(player) or not is_instance_valid(player.inventory):
		return
	if player.inventory.take_item_in_hand(item_id):
		return
	var pos := player.global_position + player.global_basis * Vector3.FORWARD * 1.2
	ItemManager.create_world_item_for(item_id, pos, player.rotation)


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
