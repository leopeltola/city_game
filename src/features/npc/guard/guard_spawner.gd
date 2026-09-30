class_name GuardSpawner
extends NpcSpawner
## [NpcSpawner] specialized for guards. In addition to the base spawn settings it can
## assign every spawned guard a shared, world-space patrol route (see
## [member patrol_route]) and the [Area3D] it watches (see [member guard_area]).

## Path every guard spawned by this node patrols. Leave empty to have them stand at
## their post. Read in world space, so it can be a level [Path3D].
@export var patrol_route: Path3D = null
## The area every guard spawned by this node watches. Needs monitoring on and its
## collision mask set to the player layer (2).
@export var guard_area: Area3D = null


func _spawn_func(data: Dictionary) -> Node:
	var npc := super(data)
	var guard := npc as Guard
	if guard != null:
		if patrol_route != null:
			guard.patrol_route = patrol_route
		if guard_area != null:
			guard.guard_area = guard_area
	return npc
