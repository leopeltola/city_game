class_name Npc
extends Humanoid
## A server-simulated, non-playable humanoid. Currently just stands still; it is
## hittable like a player, drops some of its cash on every hit and ragdolls + despawns
## when its health reaches zero. AI comes later.
##
## The server simulates the NPC (is_local = Net.is_server) so the shared melee/hit RPC
## paths replay on every peer automatically; clients only interpolate the transform.

## Cash this NPC carries. Dropped as world items when hit.
@export var cash := 100

func _ready() -> void:
	is_local = Net.is_server
	super()
	if inventory:
		inventory.mount_unarmed()


## Virtual hook from Humanoid: runs on every peer, but only the server acts.
func _on_hit_received(damage: float) -> void:
	if not Net.is_server:
		return
	else:
		_drop_cash(roundi(damage * randf_range(1, 8)))


## Spawns [amount] of the NPC's cash as a world item above it. Server only.
func _drop_cash(amount: int) -> void:
	assert(Net.is_server)
	if amount <= 0 or cash <= 0:
		return
	amount = mini(amount, cash)
	cash -= amount
	var item_id: int = ItemManager.create_item_of_type("cash", { "amount": amount })
	
	var dir := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	if dir.length_squared() < 0.01:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var force := dir * randf_range(3.0, 6.5) + Vector3.UP * randf_range(2.0, 4.0)
	ItemManager.create_world_item_for(item_id, global_position + Vector3(0.0, 1.0, 0.0), Vector3.ZERO, force)
