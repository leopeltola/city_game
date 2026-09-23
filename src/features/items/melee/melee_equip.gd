class_name MeleeEquip
extends ItemEquip
## Reusable melee engine for one-shot swing attacks plus an optional guard (RMB).
## Used by fists and bat today; future melee weapons extend it and only configure
## their `attacks` list (see _configure_attacks) and hit shape.
##
## Model:
##  - Each swing is a MeleeAttack: a rig clip with a hit window authored as method
##    keys on the clip (routed via PlayerAnimator), damage/knockback, and the set of
##    hands whose hit shapes are active during the swing (attack.hands).
##  - Hit shapes are ShapeCast3D children of HandAnchor nodes (one per hand). While
##    the window is active on the local client, the shapes whose hand is in the
##    attack's `hands` are enabled and swept between frames to catch targets.
##    Everything else (animation, flags, modifiers) is replayed on every peer via the
##    same RPCs that started the action.
##  - Attacks are picked through _pick_attack_index() so a weapon can alternate
##    swings (fists left/right) or choose by condition (future sprint shove).

enum Phase { NONE, ATTACKING, GUARDING }

## Emitted on the local client when an attack lands on a new target.
signal attack_hit(target: Node, attack: MeleeAttack)

@export var hit_sound: AudioStream = null
@export var block_sound: AudioStream = null
## Played on every peer at the start of a swing.
@export var swoosh_sound: AudioStream = null

## All swings this weapon can perform. Populated by _configure_attacks() (or exports).
@export var attacks: Array[MeleeAttack] = []

## When true, a click while a swing is still playing is buffered and chained into the
## next attack as soon as the current swing finishes (for nicer punch combos).
@export var buffer_attack_input := false

## When non-empty, RMB enters a timed guard that plays [guard_animation] and sets
## is_blocking while it lasts (legacy bat behavior). Empty disables RMB.
@export var guard_animation := ""
@export var guard_look_drag_multiplier := 0.3
@export var guard_start_blend := 0.1
@export var guard_end_blend := 0.15
## Stamina spent to raise the guard.
@export var guard_stamina_cost := 5.0

var _phase: Phase = Phase.NONE
var _active_attack: MeleeAttack = null
var _animator: ActorAnimator = null

## Set when an attack click arrives during a swing; consumed to chain the next punch.
var _pending_attack := false

## Hit shapes collected from HandAnchor children, each keyed to its hand side.
var _hit_shapes: Array[ShapeCast3D] = []
var _shape_hands: Dictionary = {}
var _prev_cast_pos: Dictionary = {}
var _hit_targets: Array[Object] = []
var _action_started_msec := 0


func _on_equipped() -> void:
	super()
	_configure_attacks()
	_melee_init()


## Virtual: subclasses / scenes populate `attacks` (and guard options). Base leaves
## whatever was exported in place.
func _configure_attacks() -> void:
	pass


func _melee_init() -> void:
	_collect_hit_shapes()
	assert(not _hit_shapes.is_empty(), "Melee equip scenes need at least one ShapeCast3D under a HandAnchor")
	for sc: ShapeCast3D in _hit_shapes:
		sc.enabled = false
		sc.add_exception(player.hittable_area)
	_ensure_animator_connected()
	_end_action()


## Registers every ShapeCast3D under a HandAnchor child, keyed to that anchor's hand.
func _collect_hit_shapes() -> void:
	_hit_shapes.clear()
	_shape_hands.clear()
	for child in get_children():
		if child is HandAnchor:
			for sc in child.get_children():
				if sc is ShapeCast3D:
					_hit_shapes.append(sc)
					_shape_hands[sc] = child.hand


func _disable_hit_shapes() -> void:
	for sc: ShapeCast3D in _hit_shapes:
		if is_instance_valid(sc):
			sc.enabled = false


## Resolves player.animator and connects the action lifecycle signals. Called on init
## and lazily on every action/physics entry so equips mounted before Player._ready ran
## (e.g. right after spawn) still attach cleanly on their first use.
func _ensure_animator_connected() -> bool:
	if is_instance_valid(_animator):
		return true
	if not is_instance_valid(player) or not is_instance_valid(player.animator):
		return false
	_animator = player.animator
	_animator.action_finished.connect(_on_animator_action_finished)
	_animator.action_cancelled.connect(_on_animator_action_cancelled)
	return true


func _on_unequipped() -> void:
	super()
	if is_instance_valid(_animator):
		if _animator.action_finished.is_connected(_on_animator_action_finished):
			_animator.action_finished.disconnect(_on_animator_action_finished)
		if _animator.action_cancelled.is_connected(_on_animator_action_cancelled):
			_animator.action_cancelled.disconnect(_on_animator_action_cancelled)
	_restore_modifiers()
	if is_instance_valid(player):
		player.is_blocking = false
		if is_instance_valid(player.animator):
			player.animator.cancel_action(0.1)
	_disable_hit_shapes()
	_phase = Phase.NONE
	_active_attack = null
	_pending_attack = false


## Helper for subclasses to build an attack entry.
func _make_attack(anim_name: String, dmg: float, knockback: float) -> MeleeAttack:
	var attack := MeleeAttack.new()
	attack.animation = anim_name
	attack.damage = dmg
	attack.knockback_force = knockback
	return attack

# --- Input (local only) ---


func _unhandled_input(event: InputEvent) -> void:
	if not player.is_local or (HUD.instance and HUD.instance.is_blocking_input()):
		return
	if event.is_action_pressed("left_click"):
		_request_attack()
	elif event.is_action_pressed("right_click"):
		_request_secondary()


func _request_attack() -> void:
	if attacks.is_empty() or player.is_action_locked():
		return
	if _phase == Phase.ATTACKING:
		# A click during a swing: buffer it so it chains the moment the swing finishes.
		if buffer_attack_input:
			_pending_attack = true
		return
	if _phase != Phase.NONE:
		return
	var index := _pick_attack_index()
	if index < 0 or index >= attacks.size():
		return
	if not player.consume_stamina(attacks[index].stamina_cost):
		return
	_rpc_do_attack.rpc(index)


## Triggers an attack without input handling. Used by AI-driven actors (e.g. the
## police baton). Returns true if a swing was started.
func try_attack() -> bool:
	if attacks.is_empty() or player == null or player.is_action_locked():
		return false
	if _phase != Phase.NONE:
		return false
	var index := _pick_attack_index()
	if index < 0 or index >= attacks.size():
		return false
	if not player.consume_stamina(attacks[index].stamina_cost):
		return false
	_rpc_do_attack.rpc(index)
	return true


## RMB secondary: legacy feint-cancel while a swing is winding up, or a guard when idle.
func _request_secondary() -> void:
	if player.is_action_locked():
		return
	if _phase == Phase.ATTACKING:
		if guard_animation != "" and _phase_started_within(0.5):
			_rpc_interrupt.rpc(0.2)
	elif _phase == Phase.NONE and guard_animation != "":
		if not player.consume_stamina(guard_stamina_cost):
			return
		_rpc_do_guard.rpc()


## Virtual: which attack from `attacks` to perform next. Base always uses the first.
func _pick_attack_index() -> int:
	return 0

# --- Action RPCs (replayed on every peer, matching the legacy bat network model) ---


@rpc("any_peer", "call_local", "reliable")
func _rpc_do_attack(index: int) -> void:
	if index < 0 or index >= attacks.size():
		return
	if not _ensure_animator_connected():
		return
	_pending_attack = false
	var attack := attacks[index]
	_action_started_msec = Time.get_ticks_msec()
	player.is_blocking = false

	# Play first so a cancel emitted for any previous action fully settles (resetting
	# modifiers) before we claim this swing's state.
	player.animator.play_action(attack.animation, attack.start_blend, attack.end_blend)
	_play_sfx_local("swoosh")

	_phase = Phase.ATTACKING
	_active_attack = attack
	player.look_drag_multiplier = attack.look_drag_multiplier
	player.move_speed_multiplier = attack.move_speed_multiplier

	if player.is_local:
		_disable_hit_shapes()
		_hit_targets.clear()


@rpc("any_peer", "call_local", "reliable")
func _rpc_do_guard() -> void:
	if guard_animation.is_empty():
		return
	if not _ensure_animator_connected():
		return
	_action_started_msec = Time.get_ticks_msec()
	player.animator.play_action(guard_animation, guard_start_blend, guard_end_blend)

	_phase = Phase.GUARDING
	_active_attack = null
	player.is_blocking = true
	player.look_drag_multiplier = guard_look_drag_multiplier
	player.move_speed_multiplier = 1.0


## Interrupts the current action (attack cancel, hit/block stagger).
@rpc("any_peer", "call_local", "reliable")
func _rpc_interrupt(blend_time: float) -> void:
	if player.animator != null:
		player.animator.cancel_action(blend_time)
	_end_action()


## Staggers the attacker (their attack was blocked): plays the stagger clip and locks
## combat / slot-switch input for its duration.
@rpc("any_peer", "call_local", "reliable")
func _rpc_stagger() -> void:
	_end_action()
	if is_instance_valid(player):
		player.enter_stagger()


@rpc("any_peer", "call_local", "reliable")
func _rpc_play_sfx(id: StringName) -> void:
	var stream: AudioStream
	match id:
		"hit":
			stream = hit_sound
		"block":
			stream = block_sound
		_:
			return
	if stream != null:
		Audio.play_sfx_3d(stream, global_position, 0, 10)


func _play_sfx_local(id: StringName) -> void:
	var stream: AudioStream
	match id:
		"swoosh":
			stream = swoosh_sound
		_:
			return
	if stream != null:
		Audio.play_sfx_3d(stream, global_position, 0, 10)

# --- Hit detection (local only, while the swing's hit window is active) ---
# The window itself is authored on the rig clip's Method track: PlayerAnimator
# receives on_hit_window_start/on_hit_window_end and routes them here, so the shape
# is enabled/disabled exactly when the track says so.


func _physics_process(_delta: float) -> void:
	if not player.is_local or _phase != Phase.ATTACKING:
		return
	for sc: ShapeCast3D in _hit_shapes:
		if not sc.enabled:
			continue
		# Sweep the shape between last frame's position and now so fast swings don't tunnel.
		sc.target_position = sc.to_local(_prev_cast_pos[sc])
		sc.force_shapecast_update()
		for i in sc.get_collision_count():
			_resolve_hit(sc.get_collider(i))
			if _phase != Phase.ATTACKING:
				return # staggered/blocked: the swing was cut short, stop registering
		_prev_cast_pos[sc] = sc.global_position


## Called by PlayerAnimator when the swing's method track enters the hit window.
## (Routed to the currently equipped MeleeEquip; local peer only.) Only the shapes on
## hands listed in the active attack's `hands` are enabled.
func on_hit_window_start() -> void:
	if not player.is_local or _phase != Phase.ATTACKING:
		return
	_hit_targets.clear()
	var attack := _active_attack
	for sc: ShapeCast3D in _hit_shapes:
		var active: bool = attack.hands.is_empty() or (_shape_hands[sc] in attack.hands)
		sc.enabled = active
		if active:
			_prev_cast_pos[sc] = sc.global_position


## Called by PlayerAnimator when the swing's method track leaves the hit window.
func on_hit_window_end() -> void:
	if not player.is_local:
		return
	_disable_hit_shapes()


func _resolve_hit(collider: Object) -> void:
	if collider in _hit_targets:
		return
	_hit_targets.append(collider)

	var attack := _active_attack
	var target: Node = collider.get_parent()
	if target == null or not target.has_method("get_hit"):
		return

	if target.get("is_blocking") == true:
		if attack.stagger_on_block:
			_rpc_stagger.rpc()
		else:
			_rpc_interrupt.rpc(attack.block_blend)
		if target.has_method("trigger_block_success"):
			target.trigger_block_success()
		_rpc_play_sfx.rpc("block")
		return

	var target3d := target as Node3D
	var force := (target3d.global_position - player.global_position).normalized() * attack.knockback_force
	force.y += 2.0
	target.get_hit(attack.damage, force, attack.interrupts_target, attack.ragdoll)
	_rpc_play_sfx.rpc("hit")
	attack_hit.emit(target, attack)
	_register_assault_guilt(target, attack)
	if attack.stagger_on_hit:
		_rpc_interrupt.rpc(attack.hit_blend)


## Adds assault guilt to a player attacker when they land a hit on another actor.
## Runs on the local client, where hit detection happens. Duck-typed so this file
## doesn't reference Player/Npc (avoids a class cycle through the weapon scenes).
func _register_assault_guilt(target: Node, attack: MeleeAttack) -> void:
	var attacker_id: Variant = player.get("player_id")
	if attacker_id == null or int(attacker_id) == 0:
		return
	if not target.has_method("get_crime_label"):
		return

	var label := "Assaulted %s" % target.call("get_crime_label")
	var amount := maxi(25, roundi(attack.damage * 4.0))
	CrimeManager.add_guilt(int(attacker_id), label, 90, amount)

# --- Action lifecycle ---


func _on_animator_action_finished(_anim_name: StringName) -> void:
	_end_action()
	if _pending_attack:
		# A click was buffered during the swing: chain straight into the next attack.
		_pending_attack = false
		_request_attack()


func _on_animator_action_cancelled(_anim_name: StringName) -> void:
	_pending_attack = false
	_end_action()


func _end_action() -> void:
	_phase = Phase.NONE
	_active_attack = null
	_disable_hit_shapes()
	_restore_modifiers()
	if is_instance_valid(player):
		player.is_blocking = false


func _restore_modifiers() -> void:
	if not is_instance_valid(player):
		return
	player.look_drag_multiplier = 1.0
	player.move_speed_multiplier = 1.0


func _phase_started_within(seconds: float) -> bool:
	return (Time.get_ticks_msec() - _action_started_msec) <= int(seconds * 1000.0)
