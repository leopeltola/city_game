class_name FistsEquip
extends MeleeEquip
## Unarmed combat gear mounted whenever the player's active slot is empty. Bare
## hands: this equip carries no mesh - the rig's own hands are animated by the
## punch clips (fists_up_punch_left / _right). Two quick jabs alternate on LMB;
## RMB is currently unbound (reserved for a future sprint shove).
##
## Scene layout: two HandAnchors (RIGHT + LEFT), each holding a ShapeCast3D at the
## corresponding fist. Each punch only enables the shape on the punching hand.

var _last_punch := -1


func _configure_attacks() -> void:
	if not attacks.is_empty():
		return
	buffer_attack_input = true
	attacks = [
		_make_punch("fists_up_punch_left", HandAnchor.HandSide.LEFT),
		_make_punch("fists_up_punch_right", HandAnchor.HandSide.RIGHT),
	]


func _make_punch(anim_name: String, hand: HandAnchor.HandSide) -> MeleeAttack:
	var punch := _make_attack(anim_name, 2.0, 4.0)
	punch.hands = [hand]
	punch.start_blend = 0.08
	punch.end_blend = 0.08
	punch.move_speed_multiplier = 0.9
	punch.look_drag_multiplier = 0.7
	punch.stamina_cost = 8.0
	punch.stagger_on_hit = false # jabs keep their flow; bat swings cut short for impact
	punch.interrupts_target = false # light jabs never cancel the victim's action
	punch.stagger_on_block = true
	punch.hit_blend = 0.1
	punch.block_blend = 0.45
	return punch


## Alternates left/right punches; a fresh combo (no punch thrown yet on this mount)
## always starts with the left fist.
func _pick_attack_index() -> int:
	if attacks.is_empty():
		return -1
	if _last_punch == -1:
		_last_punch = _index_of_hand(HandAnchor.HandSide.LEFT)
		return _last_punch
	_last_punch = (_last_punch + 1) % attacks.size()
	return _last_punch


func _index_of_hand(hand: HandAnchor.HandSide) -> int:
	for i in attacks.size():
		if attacks[i].hands.has(hand):
			return i
	return 0
