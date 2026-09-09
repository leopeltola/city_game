class_name MeleeAttack
extends Resource
## Describes a single melee swing: which rig animation plays, its damage/knockback
## and swing modifiers. The "active" hit window is NOT defined here - it is authored
## as method-track keys (on_hit_window_start / on_hit_window_end) on the rig clip's
## Method track (targeting the PlayerAnimator), so it is visible and tunable on the
## animation timeline itself.

@export var animation := ""
## Blend time (seconds) used when starting this swing, so the clip eases in from the
## idle pose instead of snapping.
@export var start_blend := 0.15
## Blend time (seconds) used when the swing's clip ends, easing back to the idle pose
## instead of snapping.
@export var end_blend := 0.15
## Hands whose hit shapes are active during this swing. Empty array = all registered
## shapes active. Fists: left jab -> [LEFT], right jab -> [RIGHT]. Bat: [RIGHT].
@export var hands: Array[HandAnchor.HandSide] = [HandAnchor.HandSide.RIGHT]
## Damage dealt by this attack.
@export var damage := 25.0
## Horizontal knockback applied away from the attacker (plus a fixed upward lift).
@export var knockback_force := 10.0

## Player movement / look modifiers applied for the whole swing.
@export var move_speed_multiplier := 1.0
@export var look_drag_multiplier := 1.0

## Whether landing a hit (or being blocked) cuts the swing short, blending to idle
## after [hit_blend] / [block_blend]. Landing a hit mid-swing also keeps one swing
## from registering the same target repeatedly.
@export var stagger_on_hit := true
@export var hit_blend := 0.5
@export var block_blend := 0.85
