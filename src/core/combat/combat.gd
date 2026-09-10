class_name Combat
extends Object
## Shared combat rules used across weapons and damageable entities. Kept as static
## helpers so future weapons/effects can reuse the same numbers without duplicating
## balance logic in data files.

## Chance (0..1) that a hit of [param damage] knocks an item out of the victim.
## Damage below 10 scales linearly (1 -> 0.1, 2 -> 0.2, ...); 10+ always drops.
static func item_drop_chance(damage: float) -> float:
	return clampf(damage / 10.0, 0.0, 1.0)
