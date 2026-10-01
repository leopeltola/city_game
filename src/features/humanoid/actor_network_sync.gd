class_name ActorNetworkSync
extends Node
## Interpolates the owner's body toward the authoritative network_position/rotation
## on remote peers. The local actor (players on their peer, NPCs on the server)
## writes those each physics frame; everyone else eases toward them here.

## How quickly remote actors catch up to the latest synced position.
@export var interp_speed := 12.0
## Metres the rendered body may be from the authoritative transform before we snap
## instead of interpolating. Turns teleports (respawns, arrests, ragdoll resets) into
## an instant pop rather than a fast dash across the gap.
@export var max_snap_distance := 5.0
var _interp_ready := false
var disabled := false

func interpolate(delta: float) -> void:
	if disabled:
		return
	var h := owner as Humanoid
	var error_sq := h.global_position.distance_squared_to(h.network_position)
	if not _interp_ready or error_sq > max_snap_distance * max_snap_distance:
		h.global_position = h.network_position
		h.global_rotation = h.network_rotation
		_interp_ready = true
		return
	var k := 1.0 - exp(-interp_speed * delta)
	h.global_position = h.global_position.lerp(h.network_position, k)
	h.global_basis = h.global_basis.slerp(Basis.from_euler(h.network_rotation), k)
