class_name FinancesUI
extends MarginContainer
## Finances tab: the local player's bank balance, debit cards and transaction history.
##
## Rebuilds on show and whenever [MoneyManager] reports a change for the local player.

const COLOR_POSITIVE := Color(0.196, 0.612, 0.31)
const COLOR_NEGATIVE := Color(0.749, 0.243, 0.243)
const COLOR_MUTED := Color(0.441, 0.441, 0.441)

@onready var _balance_label: Label = %BalanceLabel
@onready var _cards_container: VBoxContainer = %CardsContainer
@onready var _history_container: VBoxContainer = %HistoryContainer


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	MoneyManager.balance_changed.connect(func(_player_id: int, _balance: int) -> void: _refresh_if_visible())
	MoneyManager.history_changed.connect(func(_player_id: int) -> void: _refresh_if_visible())
	MoneyManager.card_changed.connect(func(_player_id: int) -> void: _refresh_if_visible())


## Rebuilds every section from the local player's current data.
func refresh() -> void:
	var player: Player = PlayerManager.get_local_player_node_or_null()
	if player == null:
		return
	var player_id := player.player_id
	_balance_label.text = "%d€" % MoneyManager.get_balance(player_id)
	_refresh_cards(player_id)
	_refresh_history(player_id)


## Rebuilds and asks the server for the latest history. Use when the tab is opened, so a
## client that missed earlier pushes still gets the full list.
func refresh_from_server() -> void:
	MoneyManager.request_history()
	refresh()


func _refresh_if_visible() -> void:
	if visible:
		refresh()


func _on_visibility_changed() -> void:
	if visible:
		refresh_from_server()


func _refresh_cards(player_id: int) -> void:
	for child in _cards_container.get_children():
		child.queue_free()

	var ids := MoneyManager.get_card_item_ids(player_id)
	if ids.is_empty():
		_cards_container.add_child(_make_label("No debit card.", COLOR_MUTED))
		return

	for item_id: int in ids:
		var number := MoneyManager.get_card_number(item_id)
		var text := "Debit card •••• %04d" % number
		if _card_is_held(player_id, item_id):
			text += "  (in hand)"
		_cards_container.add_child(_make_label(text))


# True when the card is the local player's actively equipped item.
func _card_is_held(player_id: int, item_id: int) -> bool:
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if player == null or player.inventory == null:
		return false
	return player.inventory.get_active_item_id() == item_id


func _refresh_history(player_id: int) -> void:
	for child in _history_container.get_children():
		child.queue_free()

	var entries := MoneyManager.get_history(player_id)
	if entries.is_empty():
		_history_container.add_child(_make_label("No transactions yet.", COLOR_MUTED))
		return

	# Newest first.
	for i in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[i]
		var amount: int = entry.get("amount", 0)
		var label: String = entry.get("label", "")
		var time: int = entry.get("time", 0)
		var sign := "+" if amount >= 0 else "-"
		var color := COLOR_POSITIVE if amount >= 0 else COLOR_NEGATIVE
		_history_container.add_child(
			_make_row(
				"%s  ·  %s" % [label, _format_time(time)],
				"%s%d€" % [sign, absi(amount)],
				color,
			)
		)


func _make_label(text: String, color: Color = Color(0, 0, 0, 0)) -> Label:
	var label := Label.new()
	label.text = text
	if color != Color(0, 0, 0, 0):
		label.add_theme_color_override("font_color", color)
	return label


func _make_row(left_text: String, right_text: String, right_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var left := _make_label(left_text, COLOR_MUTED)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)

	var right := _make_label(right_text, right_color)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(right)

	return row


func _format_time(unix_time: int) -> String:
	if unix_time <= 0:
		return "--:--"
	var dt := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%02d:%02d" % [dt.hour, dt.minute]
