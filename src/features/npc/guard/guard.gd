class_name Guard
extends PatrollingNpc
## Guard NPC stationed in a building. Server-simulated like every Npc. It walks a
## patrol route while idle and watches a designated [member guard_area]: when a player
## commits a crime inside that area and the guard sees it (vision cone + line of
## sight), the guard aggros, chases them down and fights with bare fists. It disengages
## as soon as the suspect leaves the guarded area (or is lost from sight for too long)
## and returns to its post.
##
## Unlike [Police] it does not arrest suspects: it only drives them out of its zone.

## When true, logs the guard's aggro decisions to the server console. Turn off once
## guards behave as expected.
const DEBUG := true

@export_group("Guard Zone")
## The area this guard watches. A player committing a crime inside it (assault, theft,
## ...) is noticed when the guard can see them. Usually assigned by [GuardSpawner].
## The area needs monitoring on and its collision mask set to the player layer (2).
@export var guard_area: Area3D = null

var _fists: MeleeEquip = null
## Players currently inside the guarded area, keyed by player_id. Server only.
var _occupants: Dictionary[int, Player] = {}


func _ready() -> void:
	super()
	add_to_group("guard")
	if equipment != null:
		_fists = equipment.get_equipped_node() as MeleeEquip
	if _fists != null:
		# The NPC is server-local; make sure the host's input never throws a punch.
		_fists.set_process_unhandled_input(false)
	if not is_local:
		return
	if _fists == null:
		push_warning("Guard '%s' has no melee equip mounted; it will chase but never punch." % name)
	if guard_area == null:
		push_warning("Guard '%s' has no guard_area; it will react anywhere it can see." % name)
	else:
		# The guard owns its zone: make sure the area detects players no matter how it
		# was authored in the scene (a fresh Area3D masks layer 1, not the player layer).
		guard_area.monitoring = true
		guard_area.set_collision_mask_value(2, true)
		guard_area.body_entered.connect(_on_area_body_entered)
		guard_area.body_exited.connect(_on_area_body_exited)
		_seed_occupants.call_deferred()
	CrimeManager.crime_committed.connect(_on_crime_committed)
	_log("ready: area=%s fists=%s" % [guard_area, _fists])


## Logs a decision to the server console when [constant DEBUG] is on.
func _log(message: String) -> void:
	if DEBUG:
		print("[Guard %s] %s" % [name, message])


## Picks up players already inside the zone when the guard connects, so a guard
## spawning on top of someone still reacts.
func _seed_occupants() -> void:
	if guard_area == null:
		return
	await get_tree().physics_frame
	for body: Node3D in guard_area.get_overlapping_bodies():
		_on_area_body_entered(body)


## Crime label used when a player assaults this guard.
func get_crime_label() -> String:
	return "a guard"


## Tracks players entering the guarded area so crime/disengage checks can use membership.
func _on_area_body_entered(body: Node3D) -> void:
	if body is Player:
		_occupants[body.player_id] = body


func _on_area_body_exited(body: Node3D) -> void:
	if body is Player:
		_occupants.erase(body.player_id)


## Reacts to a crime recorded on the server: aggros only when the culprit is inside the
## guarded area and currently visible.
func _on_crime_committed(player_id: int, _label: String) -> void:
	if not is_local or _target != null:
		return
	var player: Player = PlayerManager.get_player_node_by_id(player_id)
	if player == null or not is_instance_valid(player):
		_log("crime by %s ignored: no player node" % player_id)
		return
	if not _is_in_area(player):
		_log("crime by %s ignored: outside area" % player_id)
		return
	if not _can_see(player):
		_log("crime by %s ignored: no line of sight" % player_id)
		return
	_log("aggro on %s (witnessed '%s')" % [player_id, _label])
	_aggro(player)


## Guards also turn on whoever attacks them, even from outside the vision cone.
func _on_hit_received(damage: float, attacker_id: int = 0) -> void:
	super(damage, attacker_id)
	if not is_local or attacker_id <= 0:
		return
	var attacker: Player = PlayerManager.get_player_node_by_id(attacker_id)
	if attacker == null or not is_instance_valid(attacker):
		return
	_face(attacker.global_position - global_position)
	_log("attacked by %s: aggro" % attacker_id)
	_aggro(attacker)


# --- PatrollingNpc hooks ---


## Drops the target once it leaves the guarded area, is downed, or has been out of
## sight past the grace period.
func _is_target_valid(target: Player) -> bool:
	return is_instance_valid(target) and not target.arrested and _is_in_area(target)


func _attack_weapon() -> MeleeEquip:
	if _fists == null and equipment != null:
		_fists = equipment.get_equipped_node() as MeleeEquip
	return _fists


## True while [param player] is inside the guarded area. With no area assigned the guard
## watches everywhere (and warns about it on ready).
func _is_in_area(player: Player) -> bool:
	if guard_area == null:
		return true
	return _occupants.has(player.player_id)
