class_name Humanoid
extends CharacterBody3D
## Shared base for every on-foot actor (players and NPCs). Owns the common machinery
## - animation, status effects, locomotion, ragdoll, equip mounting and transform
## networking - and exposes the combat target API (get_hit, is_blocking, ...) that
## melee weapons hit through duck-typing.
##
## Player and Npc extend this and add their own input, camera, stamina/inventory and
## AI. network_position/rotation are written by the local actor (players on their
## peer, NPCs on the server) and interpolated on remote peers by ActorNetworkSync.

## Multiplier applied to mouse look sensitivity. Lower values simulate drag/resistance.
var look_drag_multiplier := 1.0
## Multiplier applied to movement speed.
var move_speed_multiplier := 1.0
var is_blocking := false
var is_sprinting := false
## True for the actor driven by local input / simulation (players on their peer,
## NPCs on the server). Gates input handling and local-only hit detection.
var is_local := false
## The local player's camera (players only). The ragdoll follows it while down.
var camera: Camera3D = null

@export_group("Hit Reaction")
## Speed multiplier applied while the on-hit movement debuff is active.
@export var hit_slow_multiplier: float = 0.5
## Debuff duration = base + damage * per_damage, clamped to [base, max].
@export var hit_slow_base_duration: float = 0.5
@export var hit_slow_per_damage: float = 0.1
@export var hit_slow_max_duration: float = 3.0
## Rig clip played when staggered (by a blocked attack or an interrupting hit).
@export var stagger_animation: String = "stagger"
## Blend used to enter/leave the stagger clip.
@export var stagger_blend: float = 0.1
## Fallback lock duration when the stagger clip is not imported yet.
@export var stagger_fallback_duration: float = 0.8

const SLOW_EFFECT_ID := &"hit_slow"
const STAGGER_EFFECT_ID := &"stagger"

## Mounts the hand equip (item, camera or unarmed fists). Present on every actor.
@export var equipment: EquipHost = null
## The actor's item inventory. Players have one (slots, cash, drops); NPCs don't.
@export var inventory: PlayerInventory = null
## The base body mesh (torso/limbs) a worn torso prop replaces. Assigned in the scene;
## hidden by [PropSystem] while the TORSO slot is filled.
@export var body_mesh: MeshInstance3D = null

@onready var animator: ActorAnimator = %PlayerAnimator
@onready var status: ActorStatus = %ActorStatus
@onready var locomotion: ActorLocomotion = %ActorLocomotion
@onready var ragdoll: ActorRagdoll = %ActorRagdoll
@onready var network_sync: ActorNetworkSync = %ActorNetworkSync
@onready var prop_system: PropSystem = %PropSystem
@onready var hittable_area: Area3D = %HittableArea
@onready var hittable_area_col_shape: CollisionShape3D = %HittableAreaCollisionShape
@onready var skeleton: Skeleton3D = $Visual/guy/Armature/Skeleton3D
@onready var physical_bones: PhysicalBoneSimulator3D = $Visual/guy/Armature/Skeleton3D/PhysicalBoneSimulator3D
@onready var movement_collision: CollisionShape3D = $CollisionShape3D

## Authoritative world transform written by the local actor and replicated via
## MultiplayerSynchronizer. Remote peers interpolate their body toward these.
## Vector3.INF means "not assigned yet": the network spawn state (which Godot applies
## before _ready) leaves a finite value behind, so _ready can tell the two apart.
var network_position: Vector3 = Vector3.INF
var network_rotation: Vector3 = Vector3.INF

## Marks whether the actor is ragdolled, blocks actions etc.
var is_ragdolled: bool:
	get:
		return is_instance_valid(ragdoll) and ragdoll.is_ragdolled


func _ready() -> void:
	# Godot applies the MultiplayerSynchronizer spawn state before _ready. Only seed
	# from the local transform when nothing assigned them yet (the authority actor, or
	# a non-networked instance such as CharacterPortrait); otherwise we would clobber
	# the authoritative position a remote peer just received.
	if not network_position.is_finite():
		network_position = global_position
		network_rotation = global_rotation
	else:
		# ActorNetworkSync only copies network_position onto the body in
		# _physics_process, so without this the actor would render at the spawner's
		# static transform for a frame before snapping to its real position.
		global_position = network_position
		global_rotation = network_rotation
	ragdoll.set_bone_collision(false)


func _physics_process(delta: float) -> void:
	hittable_area_col_shape.disabled = is_ragdolled # Can't be hit if ragdolled
	if is_ragdolled:
		# The physics ragdoll simulates on every peer (started through the shared
		# _rpc_get_hit), so each peer sees the same flop. ActorRagdoll owns the whole
		# flop/rise timeline and the origin tracking; while flopped the normal transform
		# interpolation is skipped so it cannot fight the local simulation.
		ragdoll.tick(delta)
		return

	if not is_local:
		network_sync.interpolate(delta)
		return

	_update_locomotion()
	locomotion.step(delta)

	network_position = global_position
	network_rotation = global_rotation


## Virtual: feeds locomotion.desired_direction / run_requested before the physics step.
func _update_locomotion() -> void:
	pass


## Returns equipped item if any exists (including unarmed gear like fists). Null otherwise.
func get_equipped_item() -> ItemEquip:
	return equipment.get_equipped_node() if equipment else null


## Returns true if player is currently holding an item of [param item_type_name] in hand.
func has_item_of_type_equipped(item_type_name: StringName) -> bool:
	var item := get_equipped_item()
	return item and item.item_type and item.item_type.name == item_type_name


## True while a status effect (e.g. stagger) locks combat and slot-switch input.
func is_action_locked() -> bool:
	return is_ragdolled or status.is_action_locked()


## Virtual: whether running is allowed right now. Players gate by stamina; the base
## (NPCs) always allows it.
func can_sprint() -> bool:
	return true


## Virtual: consumes a fixed amount of stamina. Returns true if the cost was met.
## Players drain real stamina; the base (NPCs) has no stamina and always succeeds.
func consume_stamina(_amount: float) -> bool:
	return true


## Virtual: whether the actor has at least the specified amount of stamina. Always
## true for actors without a stamina system.
func has_stamina(_amount: float) -> bool:
	return true


## Virtual hook called after a hit is applied (on every peer). Players kick the
## camera and may drop an item; NPCs lose health and drop cash. [param attacker_id] is
## the attacking player, or 0 for non-player sources.
func _on_hit_received(_damage: float, _attacker_id: int = 0) -> void:
	pass


## Virtual hook called by [ActorRagdoll] when the actor enters or leaves an active
## ragdoll. Subclasses can react (e.g. raise the transform sync rate while flying).
func _on_ragdoll_state_changed(_active: bool) -> void:
	pass


## Virtual: human-readable noun for this actor, used in crime labels
## (e.g. "Assaulted a civilian"). Subclasses override.
func get_crime_label() -> String:
	return "a person"


## Plays the stagger clip and locks combat / slot switching for its duration.
func enter_stagger() -> void:
	var effect := StatusEffect.new()
	effect.id = STAGGER_EFFECT_ID
	effect.duration = _stagger_duration()
	effect.locks_actions = true
	status.add(effect)

	if is_instance_valid(animator) and is_instance_valid(animator.anim_player) \
			and animator.anim_player.has_animation(stagger_animation):
		animator.play_action(stagger_animation, stagger_blend, stagger_blend)


## Length of the stagger clip if imported, else the configured fallback.
func _stagger_duration() -> float:
	if is_instance_valid(animator) and is_instance_valid(animator.anim_player):
		var clip := animator.anim_player.get_animation(stagger_animation)
		if clip != null:
			return clip.length
	return stagger_fallback_duration


## Triggers a quick block recovery network call.
func trigger_block_success() -> void:
	_rpc_trigger_block_success.rpc()


## Applies damage and knockback to the actor and resolves hit reactions.
## [param interrupt] when true and the actor is mid-action, the hit staggers them.
## [param ragdoll] when true, the hit flops the actor into a physics ragdoll
## (thrown by [param force]) instead of the regular stagger response.
## [param attacker_id] is the attacking player, or 0 for non-player sources.
func get_hit(
	damage: float,
	force: Vector3 = Vector3.ZERO,
	interrupt: bool = true,
	ragdoll: bool = false,
	attacker_id: int = 0,
) -> void:
	_rpc_get_hit.rpc(damage, force, interrupt, ragdoll, attacker_id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_get_hit(
	damage: float,
	force: Vector3,
	interrupt: bool,
	ragdoll: bool,
	attacker_id: int,
) -> void:
	velocity += force
	_apply_hit_slow(damage)
	_on_hit_received(damage, attacker_id)

	# A ragdoll hit restarts the flop even mid-ragdoll: the body is lying there and must
	# react, not slide along the floor. A non-ragdoll hit only adds knockback (already
	# applied above) and is ignored while down.
	if is_ragdolled:
		if ragdoll:
			self.ragdoll.start(force)
		return

	if ragdoll:
		self.ragdoll.start(force)
	elif interrupt and is_instance_valid(animator) and animator.is_action_playing():
		enter_stagger()


## Applies the temporary on-hit movement debuff; duration scales with damage.
func _apply_hit_slow(damage: float) -> void:
	var effect := StatusEffect.new()
	effect.id = SLOW_EFFECT_ID
	effect.duration = clampf(
		hit_slow_base_duration + damage * hit_slow_per_damage,
		hit_slow_base_duration,
		hit_slow_max_duration
	)
	effect.move_speed_multiplier = hit_slow_multiplier
	effect.can_sprint = false
	status.add(effect)


@rpc("any_peer", "call_local", "reliable")
func _rpc_trigger_block_success() -> void:
	is_blocking = false
	animator.cancel_action(0.1)
