class_name ActorStatus
extends Node
## Aggregates the actor's active timed status effects (slow, stagger, ...) and
## exposes the resulting movement / input gates. Combat code only ever adds or
## removes effects; the Humanoid reads the computed getters, so multiple sources can
## affect the actor at once without overwriting each other's modifiers.

signal changed

## id -> { effect: StatusEffect, end_msec: int }
var _active: Dictionary = {}


## Applies [param effect], refreshing its timer if the same id is already active.
func add(effect: StatusEffect) -> void:
	_active[effect.id] = {
		"effect": effect,
		"end_msec": Time.get_ticks_msec() + int(effect.duration * 1000.0),
	}
	changed.emit()


## Removes the effect with the given [param id], if active.
func remove(id: StringName) -> void:
	if _active.erase(id):
		changed.emit()


func has(id: StringName) -> bool:
	return _active.has(id)


func _process(_delta: float) -> void:
	if _active.is_empty():
		return
	var now := Time.get_ticks_msec()
	var expired := false
	for id: StringName in _active.keys():
		if now >= _active[id]["end_msec"]:
			_active.erase(id)
			expired = true
	if expired:
		changed.emit()


## Product of every active effect's movement multiplier.
func move_speed_multiplier() -> float:
	var multiplier := 1.0
	for entry: Dictionary in _active.values():
		multiplier *= (entry["effect"] as StatusEffect).move_speed_multiplier
	return multiplier


## True only if every active effect permits sprinting.
func can_sprint() -> bool:
	for entry: Dictionary in _active.values():
		if not (entry["effect"] as StatusEffect).can_sprint:
			return false
	return true


## True if any active effect locks combat / slot-switch input.
func is_action_locked() -> bool:
	for entry: Dictionary in _active.values():
		if (entry["effect"] as StatusEffect).locks_actions:
			return true
	return false
