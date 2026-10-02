class_name MissionLocation
extends Interactable
## A fixed delivery spot (bank, casino, ...). Handing in a pizza box that was assigned to
## this location by the [PizzaMissionBoard] pays the box's reward in cash.
##
## Every instance self-registers under its [member location_name], so destinations are
## discovered through [method get_all] without any manual wiring in the board. Users only
## ever deal with the [StringName] name; the node itself supplies the world position.

const CASH_SFX: AudioStream = preload("res://assets/sfx/slot_machine/cash_register.ogg")

@export var location_name: StringName = &""

static var _by_name: Dictionary[StringName, MissionLocation] = { }


## Returns the registered location with [param name], or null if none is placed.
static func get_location(name: StringName) -> MissionLocation:
	return _by_name.get(name)


## Returns every registered location. Used by the board to pick a destination.
static func get_all() -> Array[MissionLocation]:
	var out: Array[MissionLocation] = []
	out.assign(_by_name.values())
	return out


func _ready() -> void:
	if location_name != &"":
		_by_name[location_name] = self


func _exit_tree() -> void:
	if _by_name.get(location_name) == self:
		_by_name.erase(location_name)


## The name stored on delivery notes and used to match incoming boxes.
func get_location_name() -> StringName:
	return location_name


## Where deliveries (and cash that does not fit an inventory) land.
func get_delivery_position() -> Vector3:
	return (%DropPoint as Node3D).global_position


func get_prompt(player_id: int) -> String:
	return prompt if can_interact(player_id) else ""


func can_interact(player_id: int) -> bool:
	var box_id := _deliverable_box_id(player_id)
	return box_id != -1 and int(ItemManager.get_item_data(box_id, &"reward", 0)) > 0


func interact(player_id: int) -> void:
	deliver(player_id)


## Consumes the player's matching box and pays its reward in cash. Authority-only work
## (inventory writes) happens on the acting player's own client.
func deliver(player_id: int) -> void:
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if player == null or not player.is_multiplayer_authority():
		return
	var box_id := _deliverable_box_id(player_id)
	if box_id == -1:
		return
	var reward := int(ItemManager.get_item_data(box_id, &"reward", 0))

	var inventory := player.inventory as PlayerInventory
	inventory.pop_active_item()
	ItemManager.destroy_item(box_id)
	_give_cash(player, reward)


# Returns the held pizza box's id when it is non-empty and noted for this location, else -1.
func _deliverable_box_id(player_id: int) -> int:
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if player == null or not active:
		return -1
	var item := player.get_equipped_item()
	if item == null or item.item_type == null or item.item_type.name != "pizza_box":
		return -1
	if ItemManager.get_item_data(item.item_id, &"is_empty", true) == true:
		return -1
	if ItemManager.get_item_data(item.item_id, &"location", &"") != location_name:
		return -1
	return item.item_id


# Creates cash worth [param amount] and puts it in the player's inventory, dropping it at
# the delivery spot only when there is no room.
func _give_cash(player: Player, amount: int) -> void:
	if amount <= 0:
		return
	var cash_id := ItemManager.create_item_of_type(&"cash", { &"money": amount })
	if not (player.inventory as PlayerInventory).try_add_item(cash_id):
		ItemManager.create_world_item_for(cash_id, get_delivery_position(), Vector3.ZERO)
	Audio.play_sfx_3d(CASH_SFX, get_delivery_position(), -6.0, 25.0, true)
