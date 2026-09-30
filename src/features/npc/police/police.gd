class_name Police
extends PatrollingNpc
## Police officer NPC. Server-simulated like every Npc. It watches for wanted players
## (vision cone + line of sight), chases them, beats them down with a baton and, once
## the suspect is ragdolled and within reach, arrests them: CrimeManager confiscates
## their belongings and the target client is escorted to a free jail cell.
##
## When idle it can walk a patrol route (see [member patrol_route]); without one it
## just stands at its spawn position.

const BATON_SCENE := preload("res://src/features/items/data/police_baton/police_baton_equip.tscn")

@export_group("Arrest")
## Distance at which a ragdolled suspect can be cuffed.
@export var arrest_range := 2.0

@export_group("Jail Key")
## Chance the officer drops its belt key each time it is hit.
@export_range(0.0, 1.0) var key_drop_chance := 0.35
## Seconds after losing a key before the officer is issued a new one.
@export var key_renew_seconds := 60.0

var _baton: MeleeEquip = null
## Whether the officer is currently carrying a jail key (shown on the belt).
var has_key := true
var _key_renew_timer := 0.0

@onready var _belt_key: Node3D = %BeltJailkey


func _ready() -> void:
	super()
	add_to_group("police")
	_baton = equipment.get_equipped_node() as MeleeEquip
	if _baton != null:
		# The NPC is server-local; make sure the host's input never swings its baton.
		_baton.set_process_unhandled_input(false)
	if _belt_key != null:
		_belt_key.visible = has_key


func _mount_default_equipment() -> void:
	if equipment:
		equipment.mount_scene(BATON_SCENE)


## Crime label used when a player assaults this officer.
func get_crime_label() -> String:
	return "an officer"


## Officers drop their belt key when beaten and, when a player lands the hit, turn on
## them and put the assault straight onto their bounty. Server only: the officer's AI
## lives on the server, and facing them there puts them in the vision cone so the normal
## chase logic takes over.
func _on_hit_received(damage: float, attacker_id: int = 0) -> void:
	super(damage, attacker_id)
	if not Net.is_server:
		return
	_try_drop_key()
	if attacker_id <= 0:
		return
	var attacker: Player = PlayerManager.get_player_node_by_id(attacker_id)
	if attacker == null or not is_instance_valid(attacker):
		return
	_face(attacker.global_position - global_position)
	CrimeManager.add_bounty(attacker_id, maxi(25, roundi(damage * 4.0)))
	CrimeManager.notify_crime(attacker_id, "Assaulted an officer")


# --- PatrollingNpc hooks ---


func _on_pre_locomotion(delta: float) -> void:
	_update_key_renewal(delta)


## A wanted player is a valid suspect; one who is detained or no longer wanted is dropped.
func _is_target_valid(target: Player) -> bool:
	if not is_instance_valid(target):
		return false
	if CrimeManager.is_player_detained(target.player_id):
		return false
	return CrimeManager.is_player_wanted(target.player_id)


## The officer keeps chase only while the suspect is both in range and visible.
func _has_sight(target: Player) -> bool:
	return global_position.distance_to(target.global_position) <= vision_range and _can_see(target)


## Picks the nearest wanted player the officer can see.
func _find_suspect() -> Player:
	var best: Player = null
	var best_distance := vision_range
	for candidate: Player in PlayerManager.get_player_nodes():
		if candidate == null or not is_instance_valid(candidate):
			continue
		if not CrimeManager.is_player_wanted(candidate.player_id):
			continue
		if CrimeManager.is_player_detained(candidate.player_id) or candidate.arrested:
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance > vision_range or not _can_see(candidate):
			continue
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best


## Cuffs a downed suspect in reach; otherwise keeps walking to the body.
func _on_target_down(distance: float) -> bool:
	if distance <= arrest_range:
		_arrest()
		return true
	return false


## Follows the arrested suspect to the station.
func _do_escort() -> void:
	if _target == null or not is_instance_valid(_target) \
			or CrimeManager.is_player_detained(_target.player_id) \
			or not CrimeManager.is_player_wanted(_target.player_id):
		_target = null
		_state = State.RETURN
		return

	var distance := global_position.distance_to(_target.global_position)
	if distance > 2.0:
		move_speed_multiplier = chase_speed_multiplier
		locomotion.run_requested = true
		_navigate_to(_target.global_position)
	else:
		move_speed_multiplier = 1.0
		locomotion.desired_direction = Vector3.ZERO
		locomotion.run_requested = false
		_face(_target.global_position - global_position)


func _attack_weapon() -> MeleeEquip:
	return _baton


# --- Jail key ---


func _try_drop_key() -> void:
	if not has_key or randf() > key_drop_chance:
		return
	_set_has_key(false)

	var item_id: int = ItemManager.create_item_of_type("jail_key")
	var dir := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	if dir.length_squared() < 0.01:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var force := dir * randf_range(2.0, 4.0) + Vector3.UP * randf_range(2.0, 3.5)
	ItemManager.create_world_item_for(item_id, global_position + Vector3.UP, Vector3.ZERO, force)


func _set_has_key(value: bool) -> void:
	if not value:
		_key_renew_timer = key_renew_seconds
	_rpc_set_has_key.rpc(value)


@rpc("authority", "call_local", "reliable")
func _rpc_set_has_key(value: bool) -> void:
	has_key = value
	if _belt_key != null:
		_belt_key.visible = value


func _update_key_renewal(delta: float) -> void:
	if has_key:
		return
	_key_renew_timer -= delta
	if _key_renew_timer <= 0.0:
		_set_has_key(true)


# --- Arrest ---


## Hands the ragdolled suspect over to CrimeManager (confiscation + escort).
func _arrest() -> void:
	if _target == null:
		return
	if not CrimeManager.arrest_player(_target.player_id):
		return # no cell available; keep chasing
	_state = State.ESCORT
	move_speed_multiplier = 1.0
	locomotion.desired_direction = Vector3.ZERO
	locomotion.run_requested = false
