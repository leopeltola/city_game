class_name FistsEquip
extends MeleeEquip

var _last_punch := -1


func _configure_attacks() -> void:
	if not attacks.is_empty():
		return
	attacks = [_make_punch("fists_up_punch_left"), _make_punch("fists_up_punch_right")]


func _make_punch(anim_name: String) -> MeleeAttack:
	var punch := _make_attack(anim_name, 8.0, 4.0)
	punch.start_blend = 0.08
	punch.end_blend = 0.08
	punch.move_speed_multiplier = 0.9
	punch.look_drag_multiplier = 0.7
	punch.stagger_on_hit = false # jabs keep their flow; bat swings cut short for impact
	punch.hit_blend = 0.1
	punch.block_blend = 0.45
	return punch


## Alternates between the left/right punch clips.
func _pick_attack_index() -> int:
	if attacks.is_empty():
		return -1
	_last_punch = (_last_punch + 1) % attacks.size()
	return _last_punch
