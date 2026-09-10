class_name PhotoEquip
extends ItemEquip
## Held photo item: shows the captured image on its quad. Acquires the ImageManager
## texture while mounted and releases it on unequip, so the VRAM texture is freed
## once nothing displays it.

var _photo_id := -1
var _texture_held := false


func _on_equipped() -> void:
	super()
	_photo_id = ItemManager.get_item_data(item_id, "photo_id", -1)
	ImageManager.image_registered.connect(_on_image_registered)
	_apply_labels()
	_apply_texture()


func _on_unequipped() -> void:
	super()
	if ImageManager.image_registered.is_connected(_on_image_registered):
		ImageManager.image_registered.disconnect(_on_image_registered)
	if _texture_held:
		ImageManager.release_texture(_photo_id)
		_texture_held = false


## Shows the subject's guilt (euro label) and the photo's identifiability; hides both
## when no player was clearly captured.
func _apply_labels() -> void:
	var subject: int = ItemManager.get_item_data(item_id, "subject_player_id", 0)
	%EuroLabel.visible = subject != 0
	%PercentageLabel.visible = subject != 0
	if subject == 0:
		return
	%EuroLabel.text = "%s€" % ItemManager.get_item_data(item_id, "guilt", 0)
	%PercentageLabel.text = "%s%%" % ItemManager.get_item_data(item_id, "identifiability", 0)


func _on_image_registered(photo_id: int) -> void:
	if photo_id == _photo_id:
		_apply_texture()


func _apply_texture() -> void:
	if _texture_held or _photo_id < 0:
		return
	if not ImageManager.has_image(_photo_id):
		return
	var tex := ImageManager.acquire_texture(_photo_id)
	if tex == null:
		return
	_texture_held = true
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	$HandAnchor/photo/Plane.set_surface_override_material(1, mat)
