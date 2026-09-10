extends Node
## Central authority for capturing, syncing, and caching polaroid textures.

## Emitted on every peer when a new photo has been synchronized and stored in RAM.
signal image_registered(photo_id: int)

## Emitted when an ImageTexture is evicted from VRAM.
signal image_unloaded(photo_id: int)

var _storage: Dictionary[int, PackedByteArray] = { }
var _textures: Dictionary[int, ImageTexture] = { }
var _ref_counts: Dictionary[int, int] = { }

## Per-peer id space (peer id * ID_BASE + local sequence) so photo ids are unique
## across the network without a central allocator.
var _local_seq := 0
const ID_BASE := 1_000_000


## Streams a new photo straight to every peer and returns its photo id. No server
## relay: the caller broadcasts the image itself, so the id resolves immediately.
func register_image(webp_data: PackedByteArray) -> int:
	var photo_id := _allocate_photo_id()
	if multiplayer.has_multiplayer_peer():
		_broadcast_image.rpc(photo_id, webp_data)
	else:
		_storage[photo_id] = webp_data
		image_registered.emit(photo_id)
	return photo_id


func _allocate_photo_id() -> int:
	var peer_id := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	_local_seq += 1
	return peer_id * ID_BASE + _local_seq


@rpc("any_peer", "call_local", "reliable")
func _broadcast_image(photo_id: int, webp_data: PackedByteArray) -> void:
	_storage[photo_id] = webp_data
	image_registered.emit(photo_id)


## Increments reference count and returns the VRAM ImageTexture, creating it if absent.
func acquire_texture(photo_id: int) -> ImageTexture:
	if not _storage.has(photo_id):
		return null

	_ref_counts[photo_id] = _ref_counts.get(photo_id, 0) + 1

	if _textures.has(photo_id):
		return _textures[photo_id]

	var img: Image = Image.new()
	var err: Error = img.load_webp_from_buffer(_storage[photo_id])
	if err != OK:
		return null

	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_textures[photo_id] = tex
	return tex


## Decrements reference count and frees the VRAM texture once no consumers hold it.
func release_texture(photo_id: int) -> void:
	if not _ref_counts.has(photo_id):
		return

	_ref_counts[photo_id] -= 1
	if _ref_counts[photo_id] <= 0:
		_ref_counts.erase(photo_id)
		_textures.erase(photo_id)
		image_unloaded.emit(photo_id)


## Checks if a photo ID exists in RAM storage.
func has_image(photo_id: int) -> bool:
	return _storage.has(photo_id)
