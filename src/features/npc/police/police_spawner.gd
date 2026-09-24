class_name PoliceSpawner
extends NpcSpawner
## [NpcSpawner] specialized for police officers. In addition to the base spawn
## settings it can assign every spawned officer a shared, world-space patrol route
## (see [member patrol_route]) to loop while idle.

## Path every officer spawned by this node patrols. Leave empty to have them stand
## at their post. Read in world space, so it can be a level [Path3D].
@export var patrol_route: Path3D = null


func _spawn_func(data: Dictionary) -> Node:
	var npc := super(data)
	if patrol_route != null:
		var police := npc as Police
		if police != null:
			police.patrol_route = patrol_route
	return npc
