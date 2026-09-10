class_name StatusEffect
extends Resource
## Data describing one timed status effect (slow, stagger). 
## Applied to a PlayerStatus, which aggregates all active effects into
## the movement / input gates the rest of the player reads.

## Identifies the effect so a new application refreshes rather than stacks.
@export var id: StringName = &""
## How long the effect lasts, in seconds.
@export var duration := 1.0
## Multiplies the player's move speed for the effect's duration.
@export var move_speed_multiplier := 1.0
## When false, the player cannot sprint while this effect is active.
@export var can_sprint := true
## When true, the player cannot attack, guard, or switch item slots.
@export var locks_actions := false
