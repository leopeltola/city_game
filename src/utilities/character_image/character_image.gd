extends Node
## Caches and serves character portraits rendered from the [CharacterPortrait] rig.
##
## Usage (the call is a coroutine, so await it):
## [codeblock]
## var texture := await CharacterImage.get_full_body_portrait(player.prop_system.worn_slots)
## %Portrait.texture = texture
## [/codeblock]

## Render resolutions per framing (portrait for full body, landscape for bust).
const FULL_BODY_SIZE := Vector2i(384, 512)
const BUST_SIZE := Vector2i(512, 384)

@onready var _viewport: SubViewport = %SubViewport
@onready var _portrait: CharacterPortrait = %CharacterPortrait

## view + worn item ids -> rendered texture.
var _cache: Dictionary[String, ImageTexture] = {}


## Returns a portrait texture of [param worn_item_ids] (indexed by [enum PropSystem.PropSlot])
## rendered with [param view]. Awaits an offscreen render on a cache miss.
func get_portrait(
	worn_item_ids: Array[int],
	view: CharacterPortrait.View = CharacterPortrait.View.FULL_BODY,
) -> ImageTexture:
	var key := "%s|%s" % [view, worn_item_ids]
	if _cache.has(key):
		return _cache[key]

	_portrait.set_view(view)
	var size := _size_for(view)
	if _viewport.size != size:
		_viewport.size = size
		await get_tree().process_frame
	_portrait.set_worn(worn_item_ids)

	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw

	var image: Image = _viewport.get_texture().get_image()
	if image == null or image.is_empty():
		return null
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


## Convenience wrapper for the full-body framing.
func get_full_body_portrait(worn_item_ids: Array[int]) -> ImageTexture:
	return await get_portrait(worn_item_ids, CharacterPortrait.View.FULL_BODY)


## Convenience wrapper for the bust framing.
func get_bust_portrait(worn_item_ids: Array[int]) -> ImageTexture:
	return await get_portrait(worn_item_ids, CharacterPortrait.View.BUST)


## Drops every cached portrait texture.
func clear_cache() -> void:
	_cache.clear()


func _size_for(view: CharacterPortrait.View) -> Vector2i:
	return BUST_SIZE if view == CharacterPortrait.View.BUST else FULL_BODY_SIZE
