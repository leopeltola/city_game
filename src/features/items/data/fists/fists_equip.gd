class_name FistsEquip
extends MeleeEquip
## Unarmed combat gear mounted whenever the player's active slot is empty. Bare
## hands: this equip carries no mesh - the rig's own hands are animated by the
## punch clips (fists_up_punch_left / _right). Two quick jabs alternate on LMB;
## RMB is currently unbound (reserved for a future sprint shove).
##
## Scene layout: two HandAnchors (RIGHT + LEFT), each holding a ShapeCast3D at the
## corresponding fist. Each punch only enables the shape on the punching hand.
## The jabs themselves are authored as [MeleeAttack] resources on the scene's
## `attacks` export, left first (punch_left.tres enables the LEFT shape,
## punch_right.tres the RIGHT shape). `buffer_attack_input` is set on the scene too.

var _last_punch := -1


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
