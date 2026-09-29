class_name Citizen
extends Npc
## A civilian that wanders the safe footpaths (navigation layer 1) and flees when
## assaulted. Server-simulated like every Npc; clients interpolate its transform.
##
## Robbing is the base Npc behaviour: hits knock cash out of the citizen and looting
## that cash within the ownership window counts as theft.

const FLEE_ANIM := ActorAnimator.DEFAULT_IDLE

enum State { WANDER, PAUSE, FLEE }

@export_group("Wander")
## Random destinations are sampled on a disc of this radius around the citizen, so it
## roams the whole safe navmesh over time. The agent snaps each point onto layer 1.
@export var wander_radius := 100.0
## How close to a destination counts as arrived.
@export var arrive_distance := 1.0
## Pause length between two trips, in seconds.
@export var pause_duration := Vector2(2.0, 6.0)
## Chance a trip is a jog instead of a walk.
@export_range(0.0, 1.0) var jog_chance := 0.2
## Per-citizen pace variation applied to the base walk speed.
@export var speed_variation := 0.15

@export_group("Flee")
## How long the citizen runs after being hit, in seconds.
@export var flee_duration := Vector2(5.0, 9.0)
## How far each flee leg aims, away from the attacker.
@export var flee_distance := 18.0
## Speed multiplier while fleeing.
@export var flee_speed_multiplier := 1.0
## Seconds between flee destination refreshes.
@export var flee_repath_interval := 1.0

var _state: State = State.PAUSE
var _timer := 0.0
var _target := Vector3.INF
var _run_trip := false
var _wander_elapsed := 0.0
var _flee_from := Vector3.ZERO
var _flee_repath_timer := 0.0
var _base_speed_multiplier := 1.0


func _ready() -> void:
	super()
	_base_speed_multiplier = randf_range(1.0 - speed_variation, 1.0 + speed_variation)
	_enter_pause()


func _mount_default_equipment() -> void:
	pass


func _update_locomotion() -> void:
	if not is_local:
		return
	move_speed_multiplier = _base_speed_multiplier
	var delta := get_physics_process_delta_time()
	_timer = maxf(_timer - delta, 0.0)
	match _state:
		State.WANDER:
			_do_wander(delta)
		State.FLEE:
			_do_flee(delta)
		_:
			_do_pause()


func _do_pause() -> void:
	locomotion.desired_direction = Vector3.ZERO
	locomotion.run_requested = false
	if _timer <= 0.0:
		_target = _pick_wander_target()
		_run_trip = randf() < jog_chance
		_wander_elapsed = 0.0
		_state = State.WANDER


func _do_wander(delta: float) -> void:
	_wander_elapsed += delta
	locomotion.run_requested = _run_trip
	if global_position.distance_to(_target) <= arrive_distance \
			or (_wander_elapsed > 0.5 and _nav_agent.is_navigation_finished()):
		_enter_pause()
		return
	_navigate_to(_target)


func _do_flee(delta: float) -> void:
	if _timer <= 0.0:
		_state = State.PAUSE
		_target = Vector3.INF
		_rpc_set_flee_animation.rpc(false)
		return
	move_speed_multiplier = flee_speed_multiplier
	locomotion.run_requested = true
	_flee_repath_timer = maxf(_flee_repath_timer - delta, 0.0)
	if _target == Vector3.INF or global_position.distance_to(_target) <= arrive_distance \
			or _flee_repath_timer <= 0.0:
		_target = _pick_flee_target()
		_flee_repath_timer = flee_repath_interval
	_navigate_to(_target)


func _enter_pause() -> void:
	_state = State.PAUSE
	_timer = randf_range(pause_duration.x, pause_duration.y)
	_target = Vector3.INF
	locomotion.desired_direction = Vector3.ZERO
	locomotion.run_requested = false


func _pick_wander_target() -> Vector3:
	# A raw world point is fine: the navigation agent resolves it onto layer 1.
	var angle := randf() * TAU
	var distance := randf_range(wander_radius * 0.1, wander_radius)
	return global_position + Vector3(cos(angle), 0.0, sin(angle)) * distance


func _pick_flee_target() -> Vector3:
	var away := global_position - _flee_from
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	away = away.normalized().rotated(Vector3.UP, deg_to_rad(randf_range(-60.0, 60.0)))
	return global_position + away * flee_distance


func _on_hit_received(damage: float, attacker_id: int = 0) -> void:
	super(damage, attacker_id)
	if not Net.is_server:
		return
	var attacker: Player = null
	if attacker_id > 0:
		attacker = PlayerManager.get_player_node_by_id(attacker_id)
	if is_instance_valid(attacker):
		_flee_from = attacker.global_position
	else:
		_flee_from = global_position - Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	_timer = randf_range(flee_duration.x, flee_duration.y)
	_flee_repath_timer = 0.0
	_target = Vector3.INF
	_state = State.FLEE
	_rpc_set_flee_animation.rpc(true)


@rpc("authority", "call_local", "reliable")
func _rpc_set_flee_animation(value: bool) -> void:
	if value:
		animator.set_idle_override(FLEE_ANIM)
	else:
		animator.clear_idle_override()
