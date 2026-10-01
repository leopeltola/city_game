class_name Npc
extends Humanoid
## A server-simulated, non-playable humanoid. Base NPCs stand still and are hittable
## like a player: they drop some of their cash on every hit and ragdoll + despawn when
## their health reaches zero. Subclasses add AI (police, citizens, band players).
##
## The server simulates the NPC (is_local = Net.is_server) so the shared melee/hit RPC
## paths replay on every peer automatically; clients only interpolate the transform.

## Cash this NPC carries. Dropped as world items when hit.
@export var cash := 100

@export_group("Navigation")
## How far the current goal must drift before a new path is requested.
@export var nav_repath_distance := 0.75
## Minimum seconds between path requests once the current path has ended.
@export var nav_repath_interval := 0.25

@export_group("Network")
## Seconds between transform syncs. Lower values are smoother but cost more bandwidth.
@export var network_sync_interval := 0.1
## Peers whose player body is further than this stop receiving the NPC at all. The
## server despawns it on that peer, so it costs neither bandwidth nor client CPU.
@export var interest_radius := 60.0
## Extra range a peer keeps once it has the NPC, so NPCs do not pop in and out when
## a player walks along the edge of [member interest_radius].
@export var interest_hysteresis := 15.0

@onready var _nav_agent: NavigationAgent3D = %NavigationAgent3D
@onready var network_synchronizer: MultiplayerSynchronizer = %MultiplayerSynchronizer
## Goal currently assigned to the navigation agent.
var _nav_target := Vector3.INF
## Time left before a finished path may be re-targeted.
var _nav_repath_timer := 0.0
## Peer id -> whether that peer currently has this NPC, used to apply the hysteresis.
var _interest_peers: Dictionary[int, bool] = { }

func _ready() -> void:
	is_local = Net.is_server
	super()
	_mount_default_equipment()

	if Net.is_server:
		network_synchronizer.replication_interval = network_sync_interval
		network_synchronizer.add_visibility_filter(_is_peer_in_interest_range)
		Net.peer_disconnected.connect(_on_peer_disconnected)


## Virtual: mounts this NPC's fixed gear. Base NPCs get bare fists; subclasses can
## override to mount a dedicated weapon (e.g. the police baton).
func _mount_default_equipment() -> void:
	if equipment:
		equipment.mount_unarmed()


## Visibility filter deciding whether [param peer_id] keeps this NPC. When it returns
## false the NPC is despawned on that peer (it was spawned through a MultiplayerSpawner)
## and both sync and broadcast RPC traffic for it are skipped. Peer 0 is the "every
## peer" sentinel and must stay false, otherwise the NPC becomes public to everyone.
func _is_peer_in_interest_range(peer_id: int) -> bool:
	if not Net.is_server or peer_id == 0:
		return false
	# Never cull an actor we cannot place, or one mid-ragdoll: a flung ragdoll must
	# not be despawned on the peers watching it.
	if not global_position.is_finite() or is_ragdolled:
		return true

	var player_position: Variant = PlayerManager.get_peer_position_or_null(peer_id)
	if player_position == null:
		return true # Peer has no spawned player body yet: don't hide the world from it.
	var target: Vector3 = player_position

	var was_visible: bool = _interest_peers.get(peer_id, false)
	var radius := interest_radius + (interest_hysteresis if was_visible else 0.0)
	var in_range: bool = global_position.distance_squared_to(target) <= radius * radius
	_interest_peers[peer_id] = in_range
	return in_range


## Drops cached interest state for a peer that left.
func _on_peer_disconnected(peer_id: int) -> void:
	_interest_peers.erase(peer_id)


## Virtual hook from Humanoid: runs on every peer, but only the server acts.
func _on_hit_received(damage: float, _attacker_id: int = 0) -> void:
	if not Net.is_server:
		return
	else:
		_drop_cash(roundi(damage * randf_range(1, 8)))


## Crime label used when a player assaults this NPC.
func get_crime_label() -> String:
	return "a civilian"


## Spawns [amount] of the NPC's cash as a world item above it. Server only.
func _drop_cash(amount: int) -> void:
	assert(Net.is_server)
	if amount <= 0 or cash <= 0:
		return
	amount = mini(amount, cash)
	cash -= amount
	var item_id: int = ItemManager.create_item_of_type("cash", { "money": amount })
	
	var dir := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	if dir.length_squared() < 0.01:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var force := dir * randf_range(3.0, 6.5) + Vector3.UP * randf_range(2.0, 4.0)
	# Owned by the NPC: looting its cash within the grace window counts as stealing.
	ItemManager.create_world_item_for(
		item_id, global_position + Vector3(0.0, 1.0, 0.0), Vector3.ZERO, force, ItemWorld.NPC_OWNER_ID
	)


## Steers toward [param position] by following the navmesh path one point at a time
## through the [NavigationAgent3D]. The goal is only handed to the agent when it has
## drifted far enough to matter; from there the agent's own path points drive the
## movement (get_next_path_position), so the NPC walks the actual navmesh route instead
## of cutting straight at the goal. When the path is finished the NPC stops and leaves
## arrival/next-goal handling to the caller. Direct steering is used only when there is
## no agent at all.
func _navigate_to(position: Vector3) -> void:
	var direction := Vector3.ZERO
	if _nav_agent == null:
		direction = position - global_position
		direction.y = 0.0
	else:
		_nav_repath_timer = maxf(_nav_repath_timer - get_physics_process_delta_time(), 0.0)
		var drift := _nav_target - position
		drift.y = 0.0
		var needs_repath := drift.length_squared() > nav_repath_distance * nav_repath_distance
		if _nav_agent.is_navigation_finished() and _nav_repath_timer <= 0.0:
			needs_repath = true
		if needs_repath:
			_nav_target = position
			_nav_repath_timer = nav_repath_interval
			_nav_agent.target_position = position
		if not _nav_agent.is_navigation_finished():
			# The agent's next path point, not the final goal: walks the navmesh route.
			direction = _nav_agent.get_next_path_position() - global_position
			direction.y = 0.0
	locomotion.desired_direction = direction.normalized()
	if not locomotion.desired_direction.is_zero_approx():
		_face(direction)


## Rotates the NPC to face a world-space direction.
func _face(direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		return
	rotation.y = atan2(-direction.x, -direction.z)
