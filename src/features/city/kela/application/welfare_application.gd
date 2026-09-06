extends Interactable

func interact(player_id: int) -> void:
	if not HUD.instance:
		return
	var result := await HUD.instance.prompt_welfare()
	print(result)
	
