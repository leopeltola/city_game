class_name InformationUI
extends MarginContainer
## Information tab: shows the local player's name and a rendered portrait of their
## current outfit. Re-renders each time the tab is shown.

@onready var _portrait: TextureRect = %Portrait
@onready var _name_label: Label = %PlayerNameLabel

## Guards against a stale async render overwriting a newer request.
var _refresh_id: int = 0


## Fetches the local player's name and outfit portrait and displays them.
func refresh() -> void:
	var player: Player = PlayerManager.get_local_player_node_or_null()
	if player == null or player.prop_system == null:
		return

	if player.player_data != null:
		_name_label.text = player.player_data.player_name

	_refresh_id += 1
	var request_id := _refresh_id
	var texture := await CharacterImage.get_full_body_portrait(player.prop_system.worn_slots)
	if request_id != _refresh_id:
		return
	_portrait.texture = texture
