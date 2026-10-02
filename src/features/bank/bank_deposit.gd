extends Interactable
## Bank deposit point. Moves the held cash stack or briefcase into the actor's account.
##
## Placeholder visuals: a box mesh. Interact runs on the acting client, so the local
## player's held item is the one being deposited.

const PROMPT_DEPOSIT := "Deposit money"
const PROMPT_NEED_CASH := "Need cash to deposit"

const CASH_SFX: AudioStream = preload("res://assets/sfx/slot_machine/cash_register.ogg")


func get_prompt(player_id: int) -> String:
	return PROMPT_DEPOSIT if MoneyManager.get_held_money(player_id) > 0 else PROMPT_NEED_CASH


func can_interact(player_id: int) -> bool:
	return active and MoneyManager.get_held_money(player_id) > 0


func interact(player_id: int) -> void:
	if not HUD.instance:
		return
	var total := MoneyManager.get_held_money(player_id)
	if total <= 0:
		return

	var result := await HUD.instance.prompt_money(total, total, "Deposit money")
	if result.cancelled or result.amount <= 0:
		return
	if MoneyManager.deposit(player_id, mini(result.amount, total)):
		Audio.play_sfx_3d(CASH_SFX, global_position, -6.0, 25.0, true)
