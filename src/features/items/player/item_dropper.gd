class_name ItemDropper
extends Node
## Spawns items from a PlayerInventory into the world, and splits cash stacks when only
## part of a stack is dropped. Owns the drop-position ray nodes and the money-split
## prompt (long-press on the drop key).
##
## [b]Authority:[/b] spawning and splitting happen server-side through [ItemManager], so
## the split path is an RPC. The inventory itself stays client-authoritative.

## The actor dropping items. Supplies drop rotation/position.
@export var player: Humanoid = null
## The inventory items are taken from. Untyped to avoid a cyclic class reference.
@export var inventory: Node = null


func _ready() -> void:
	assert(player != null, "ItemDropper requires player")
	assert(inventory != null, "ItemDropper requires inventory")
	assert(%ItemDropRay != null, "ItemDropper requires an %ItemDropRay node")
	assert(%ItemDropPosition != null, "ItemDropper requires an %ItemDropPosition node")


## Drops the item currently held in the active slot in front of the player.
## [br][br]
## Authority-only.
func drop_active_item() -> void:
	assert(is_multiplayer_authority(), "drop_active_item is authority-only")

	var item_id: int = inventory.pop_active_item()
	if item_id == -1:
		return

	spawn_item(item_id, get_drop_position(), player.rotation)


## Spawns [param item_id] as a world item at [param position]. Central spawn point for
## every drop path (inventory overflow, active drop, random drop). [param owner_player_id]
## marks the item as owned (player id, 0 = nobody) so stealing it within the grace window
## counts as a crime.
func spawn_item(
	item_id: int,
	position: Vector3,
	rotation: Vector3 = Vector3.ZERO,
	force: Vector3 = Vector3.ZERO,
	owner_player_id: int = 0
) -> void:
	ItemManager.create_world_item_for(item_id, position, rotation, force, owner_player_id)


## Removes a random non-empty item from the inventory and spawns it as a world item at
## [param position] with the given launch [param force]. [param owner_player_id] marks
## the dropped item as owned so looting it counts as theft (used when the item is
## knocked out of a player rather than deliberately dropped).
## [br][br]
## Authority-only. Returns the item ID, or -1 if the inventory is empty.
func drop_random_item(position: Vector3, force: Vector3, owner_player_id: int = 0) -> int:
	assert(is_multiplayer_authority(), "drop_random_item is authority-only")

	var item_id: int = inventory.pop_random_item()
	if item_id == -1:
		return -1

	spawn_item(item_id, position, Vector3.ZERO, force, owner_player_id)
	return item_id


## Opens the money prompt to ask how much cash to drop from the held stack, then drops
## that portion. Cancels if the stack changed hands while the prompt was open.
func prompt_drop_cash(item_id: int) -> void:
	if not HUD.instance:
		return
	var total: int = ItemManager.get_item_data(item_id, "money", 0)
	if total <= 0:
		return

	var result := await HUD.instance.prompt_money(total, total, "Drop money")
	if result.cancelled or result.amount <= 0:
		return
	if inventory.get_active_item_id() != item_id:
		return

	drop_cash_amount(item_id, mini(result.amount, total))


## Drops a specific [param amount] from the cash stack held as [param item_id].
## If [param amount] covers the whole stack, the entire stack is dropped as-is.
## [br][br]
## Authority-only.
func drop_cash_amount(item_id: int, amount: int) -> void:
	assert(is_multiplayer_authority(), "drop_cash_amount is authority-only")

	var total: int = ItemManager.get_item_data(item_id, "money", 0)
	if total <= 0 or amount <= 0:
		return
	if amount >= total:
		drop_active_item()
		return

	if Net.is_server:
		_server_split_cash_drop(item_id, amount, get_drop_position())
	elif Net.is_client:
		_server_split_cash_drop.rpc_id(1, item_id, amount, get_drop_position())


# Splits a cash stack server-side: shrinks the held stack to the remainder and
# spawns the dropped portion as a new cash world item at [param position].
@rpc("any_peer", "call_remote", "reliable")
func _server_split_cash_drop(item_id: int, amount: int, position: Vector3) -> void:
	assert(Net.is_server)
	var total: int = ItemManager.get_item_data(item_id, "money", 0)
	if total <= 0 or amount <= 0 or amount >= total:
		return

	ItemManager.set_and_sync_item_data(item_id, "money", total - amount)
	var dropped_id: int = ItemManager.create_item_of_type("cash", { "money": amount })
	ItemManager.create_world_item_for(dropped_id, position)


## Returns a world position about 1.5m in front of the player, offset back from walls.
func get_drop_position() -> Vector3:
	if not %ItemDropRay.is_colliding():
		return %ItemDropPosition.global_position

	var hit_pos: Vector3 = %ItemDropRay.get_collision_point()
	var ray_origin: Vector3 = %ItemDropRay.global_position
	var pull_dir: Vector3 = (ray_origin - hit_pos).normalized()

	return hit_pos + pull_dir * 0.2
