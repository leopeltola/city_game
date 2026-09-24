extends MarginContainer
## Hotbar showing the local player's item slots with themed panels, item icons,
## money labels, a clear selected-slot highlight and toast-style juice.

const SLOT_SCENE: PackedScene = preload("res://src/features/items/player/inventory_slot.tscn")

const SFX_VOLUME_DB := -8.5

@export var inv: PlayerInventory = null
@export var pickup_sfx: AudioStream = null
@export var select_sfx: AudioStream = null

@onready var _slots_box: HBoxContainer = %Slots

var _slots: Array[InventorySlot] = []
var _prev_ids: Array[int] = []
var _prev_active := -1
var _bar_tween: Tween


func _ready() -> void:
	assert(inv != null, "ItemInventoryUI requires inv")


	_build_slots()
	inv.inventory_updated.connect(_on_inventory_updated)
	# Wait a frame so PlayerInventory._ready has sized item_slots and the slots have
	# their final size before we read state or start the entrance animation.
	await get_tree().process_frame
	_update(true)


func _on_inventory_updated() -> void:
	_update(false)


# Money amounts change on existing items without emitting inventory_updated (e.g.
# filling or draining a cash stack), so poll the count labels. Only a handful of
# slots, so this is negligible.
func _process(_delta: float) -> void:
	if inv == null or inv.item_slots.size() < _slots.size():
		return
	for i in _slots.size():
		_slots[i].set_count(_get_slot_count(inv.get_slot_item_id(i)))


# Instantiates one slot per inventory slot and lays them out in the row.
func _build_slots() -> void:
	for i in inv.slot_count:
		var slot: InventorySlot = SLOT_SCENE.instantiate() as InventorySlot
		_slots_box.add_child(slot)
		slot.set_index(i + 1)
		_slots.append(slot)
	_prev_ids.resize(inv.slot_count)
	_prev_ids.fill(-1)


# Refreshes every slot. [param initial] skips change detection and plays the
# staggered entrance instead.
func _update(initial := false) -> void:
	# Guard against running before PlayerInventory has sized its slots.
	if inv.item_slots.size() < _slots.size():
		return

	var added := false
	var active_changed := false

	for i in _slots.size():
		var item_id := inv.get_slot_item_id(i)
		var slot := _slots[i]
		var is_active := (i == inv.active_index)

		if initial:
			slot.set_slot(_get_slot_icon(item_id), _get_slot_count(item_id))
		elif item_id != _prev_ids[i]:
			slot.set_slot(_get_slot_icon(item_id), _get_slot_count(item_id))
			if item_id == -1:
				slot.play_remove()
			else:
				slot.play_add()
				added = true

		slot.set_selected(is_active)
		if not initial and is_active and i != _prev_active:
			slot.play_select()
			active_changed = true
		_prev_ids[i] = item_id

	if initial:
		_prev_active = inv.active_index
		_play_entrance()
		return

	if added:
		_play_bar_bounce()
		Audio.play_sfx(pickup_sfx, SFX_VOLUME_DB)
	elif active_changed:
		Audio.play_sfx(select_sfx, SFX_VOLUME_DB)
	_prev_active = inv.active_index


# Staggered pop-in of the whole bar.
func _play_entrance() -> void:
	for i in _slots.size():
		_slots[i].play_in(i * 0.05)


# A quick squash-bounce of the whole bar when an item is picked up.
func _play_bar_bounce() -> void:
	if _bar_tween and _bar_tween.is_valid():
		_bar_tween.kill()
	pivot_offset = size * 0.5
	_bar_tween = create_tween()
	_bar_tween.tween_property(self, "scale", Vector2(1.06, 0.94), 0.07) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_bar_tween.tween_property(self, "scale", Vector2(0.98, 1.02), 0.07) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_bar_tween.tween_property(self, "scale", Vector2.ONE, 0.14) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# Returns the icon configured on the item's type, or null for an empty slot.
func _get_slot_icon(item_id: int) -> Texture2D:
	if item_id == -1:
		return null
	var type_name := StringName(ItemManager.get_item_data(item_id, "type"))
	return ItemManager.get_item_type(type_name).icon


# Returns a label for stackable money items (cash / briefcase), or "".
func _get_slot_count(item_id: int) -> String:
	if item_id == -1:
		return ""
	var money: Variant = ItemManager.get_item_data(item_id, "money", null)
	if money is int and money > 0:
		return "%d€" % money
	return ""
