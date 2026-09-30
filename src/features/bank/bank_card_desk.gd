extends Interactable
## Bank desk. Issues a debit card for [constant MoneyManager.CARD_PRICE] (charged to the
## account) when the actor has none, or cancels their existing card.
##
## Placeholder visuals: a box mesh.

const PROMPT_BUY := "Buy debit card (500€)"
const PROMPT_NEED_FUNDS := "Need 500€ in account"
const PROMPT_CANCEL := "Cancel debit card"

## Where the card is dropped when the buyer's inventory is full.
@onready var _item_spawn: Node3D = %ItemSpawnPos


func get_prompt(player_id: int) -> String:
	if MoneyManager.has_card(player_id):
		return PROMPT_CANCEL
	if MoneyManager.get_balance(player_id) >= MoneyManager.CARD_PRICE:
		return PROMPT_BUY
	return PROMPT_NEED_FUNDS


func can_interact(player_id: int) -> bool:
	if not active:
		return false
	if MoneyManager.has_card(player_id):
		return true
	return MoneyManager.get_balance(player_id) >= MoneyManager.CARD_PRICE


func interact(player_id: int) -> void:
	if MoneyManager.has_card(player_id):
		MoneyManager.cancel_card(player_id)
		return
	MoneyManager.issue_card(player_id, _item_spawn.global_position, _item_spawn.global_rotation)
