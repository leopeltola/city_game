extends MeleeEquip
## Police baton. Config-only: a single heavy swing (same profile as the bat) used by
## the police NPCs. Unlike the bat it is unarmed gear with no backing item, mounted
## directly by Police._mount_default_equipment().

func _configure_attacks() -> void:
	if not attacks.is_empty():
		return
	var swing := _make_attack("bat_attack", 25.0, 25.0)
	swing.start_blend = 0.15
	swing.end_blend = 0.15
	swing.move_speed_multiplier = 0.75
	swing.look_drag_multiplier = 0.3
	swing.stamina_cost = 10.0
	swing.stagger_on_hit = true
	swing.interrupts_target = true
	swing.stagger_on_block = true
	swing.ragdoll = true
	swing.hit_blend = 0.5
	swing.block_blend = 0.85
	attacks.append(swing)

	guard_animation = "bat_block"
	guard_look_drag_multiplier = 0.3
	guard_stamina_cost = 5.0
