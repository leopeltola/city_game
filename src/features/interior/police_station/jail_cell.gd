class_name JailCell
extends Area3D
## The interior of a jail cell. While the cell door is closed, any player inside pays
## their bounty off at [constant JAIL_DRAIN_PER_SECOND]. Once every occupant is out of
## bounty, the door opens automatically. Server-authoritative.

## Bounty (€) paid off per second spent locked inside with the door closed.
const JAIL_DRAIN_PER_SECOND := 20

## The door that must be closed for the drain to run.
@export var door: JailDoor = null
## Where suspects are escorted to.
@export var stand_point: Node3D = null

var _occupants: Dictionary[int, Player] = {}
var _drain_accum := 0.0


func _ready() -> void:
	assert(door != null, "JailCell '%s' is missing its door export" % name)
	assert(stand_point != null, "JailCell '%s' is missing its stand_point export" % name)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	set_physics_process(Net.is_server)


## World position suspects are escorted to.
func get_stand_position() -> Vector3:
	return stand_point.global_position


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		_occupants[body.player_id] = body


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_occupants.erase(body.player_id)
		if Net.is_server:
			CrimeManager.set_detained(body.player_id, false)


func _physics_process(delta: float) -> void:
	if _occupants.is_empty() or door.is_open:
		_drain_accum = 0.0
		return

	_drain_accum += delta
	while _drain_accum >= 1.0:
		_drain_accum -= 1.0
		_drain()


## Charges every occupant one second of bounty, then opens the door if nobody inside
## is still wanted.
func _drain() -> void:
	for player_id: int in _occupants.keys():
		var player: Player = _occupants[player_id]
		if not is_instance_valid(player):
			_occupants.erase(player_id)
			continue
		var bounty: int = CrimeManager.get_player_bounty(player_id)
		if bounty > 0:
			CrimeManager.set_bounty(player_id, maxi(bounty - JAIL_DRAIN_PER_SECOND, 0))

	for player_id: int in _occupants.keys():
		if CrimeManager.get_player_bounty(player_id) > 0:
			return
	_release_occupants()


## Opens the door and frees the cell reservation for everyone inside.
func _release_occupants() -> void:
	door.set_open(true)
	for player_id: int in _occupants.keys():
		CrimeManager.set_detained(player_id, false)
