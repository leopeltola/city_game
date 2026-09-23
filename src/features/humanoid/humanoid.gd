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
var network_position: Vector3
var network_rotation: Vector3

## Marks whether the actor is ragdolled, blocks actions etc.
var is_ragdolled: bool:
	get:
		return is_instance_valid(ragdoll) and ragdoll.is_ragdolled


func _ready() -> void:
	network_position = global_position
	network_rotation = global_rotation
	_set_ragdoll_bone_collision(false)


func _process(delta: float) -> void:
	if is_instance_valid(ragdoll) and ragdoll.is_rising():
		ragdoll.process_rise(delta)


func _physics_process(delta: float) -> void:
	if not is_local:
		network_sync.interpolate(delta)
		return

	hittable_area_col_shape.disabled = is_ragdolled # Can't be hit if ragdolled
	if is_ragdolled:
		if ragdoll.is_rising():
			ragdoll.process_rise_physics(delta)
		else:
			ragdoll.process_ragdoll(delta)
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
	return item and item.item_type.name == item_type_name


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
## camera and may drop an item; NPCs lose health and drop cash.
func _on_hit_received(_damage: float) -> void:
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
func get_hit(damage: float, force: Vector3 = Vector3.ZERO, interrupt: bool = true, ragdoll: bool = false) -> void:
	_rpc_get_hit.rpc(damage, force, interrupt, ragdoll)


@rpc("any_peer", "call_local", "reliable")
func _rpc_get_hit(damage: float, force: Vector3, interrupt: bool, ragdoll: bool) -> void:
	if is_ragdolled:
		return
	velocity += force
	_apply_hit_slow(damage)
	_on_hit_received(damage)

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


## Toggles the physical bone bodies' collision so the idle kinematic bodies never
## block anyone, while an active ragdoll collides with the world.
func _set_ragdoll_bone_collision(active: bool) -> void:
	if not is_instance_valid(physical_bones):
		return
	for bone: Node in physical_bones.get_children():
		if bone is PhysicalBone3D:
			bone.collision_layer = 2 if active else 0
			bone.collision_mask = 1 if active else 0
