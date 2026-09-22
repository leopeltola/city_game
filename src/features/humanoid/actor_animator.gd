class_name ActorAnimator
extends Node
## Owns the rig AnimationPlayer: plays the persistent idle (honoring the equipped
## item's idle override) and one-shot "action" clips (attacks, guards, ...).
## Equips subscribe to the action_* signals and never poke the AnimationPlayer
## directly, so animation state stays owned in one place. Shared by players and NPCs.
##
## Both ends of an action transition are blended: play_action takes a start blend
## (idle -> action) and an end blend (action -> idle on natural finish). Cancels
## pass their own blend explicitly.

signal action_started(anim_name: StringName)
signal action_finished(anim_name: StringName)
signal action_cancelled(anim_name: StringName)

@export var humanoid: Humanoid = null
@export var anim_player: AnimationPlayer = null

var _override_anim := ""
## Name of the idle clip we currently (or last) told the AnimationPlayer to play.
## Empty means idle must be (re)started on the next process frame.
var _idle_anim := ""
## Blend to use when restarting idle (set by play_action's end blend / cancel).
var _idle_blend := 0.1


func _ready() -> void:
	assert(anim_player)
	assert(humanoid)
	anim_player.animation_finished.connect(_on_animation_finished)


func _process(_delta: float) -> void:
	if _override_anim != "":
		# An action is playing; idle must (re)start once it ends, so drop the cached name.
		_idle_anim = ""
		return
	var idle := _current_idle_name()
	if _idle_anim != idle:
		_idle_anim = idle
		anim_player.play(idle, _idle_blend)
		_idle_blend = 0.1


func _current_idle_name() -> String:
	var idle := ""
	if humanoid != null and humanoid.equipment != null:
		idle = humanoid.equipment.get_idle_animation_override()
	return idle if not idle.is_empty() else "idle"


func is_action_playing() -> bool:
	return _override_anim != ""


func current_override() -> String:
	return _override_anim


## Plays a one-shot action clip. If a different override was already playing it is
## cancelled first (emitting action_cancelled for it) so only one action runs at a time.
## [start_blend] eases into the action; [end_blend] eases back to idle when the clip
## finishes naturally (cancel uses its own blend instead).
func play_action(anim_name: String, start_blend: float = 0.1, end_blend: float = 0.1) -> void:
	if _override_anim != "" and _override_anim != anim_name:
		var prev := _override_anim
		_override_anim = ""
		action_cancelled.emit(prev)
	_override_anim = anim_name
	_idle_anim = ""
	_idle_blend = end_blend
	anim_player.play(anim_name, start_blend)
	action_started.emit(anim_name)


## Cancels the current action (if any), blending back to the idle pose.
func cancel_action(blend_time: float = 0.1) -> void:
	if _override_anim == "":
		return
	var prev := _override_anim
	_override_anim = ""
	_idle_anim = _current_idle_name()
	_idle_blend = 0.0
	anim_player.play(_idle_anim, blend_time)
	action_cancelled.emit(prev)


## Hit-window events. Authored on a rig clip's Method track (targeting this node),
## so swing timing is visible on the animation timeline itself. Routed to the
## currently equipped melee weapon, which toggles its hit shape accordingly.
func on_hit_window_start() -> void:
	var melee := _equipped_melee()
	if melee != null:
		melee.on_hit_window_start()


func on_hit_window_end() -> void:
	var melee := _equipped_melee()
	if melee != null:
		melee.on_hit_window_end()


func _equipped_melee() -> MeleeEquip:
	if humanoid == null or humanoid.equipment == null:
		return null
	return humanoid.equipment.get_equipped_node() as MeleeEquip


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name != _override_anim:
		return
	_override_anim = ""
	# _idle_anim stays "" so _process restarts idle using the pending end blend.
	action_finished.emit(anim_name)
