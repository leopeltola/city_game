class_name ServerProcess
extends RefCounted

## Launches and tracks the headless game server process for a player-hosted lobby.
##
## The child is the same executable as the running game: from the editor that is the
## Godot binary (so it needs an explicit project path), from an exported build it is the
## game binary itself. It is told to boot in dedicated-server mode via project CLI args.

var pid: int = -1


## Spawns a detached headless server for [param room_id]. Returns [code]OK[/code] on
## success or [code]FAILED[/code] if the process could not be created.
func spawn(room_id: String, leader_token: String, capacity: int) -> Error:
	var executable := OS.get_executable_path()
	var args := PackedStringArray()

	# Exported games embed their packs, but the editor binary needs to be pointed at
	# the project explicitly. OS.has_feature("editor") distinguishes the two.
	if OS.has_feature("editor"):
		args.append("--path")
		args.append(ProjectSettings.globalize_path("res://"))

	args.append("--headless")
	args.append("--dedicated-server")
	args.append("--room")
	args.append(room_id)
	args.append("--leader-token")
	args.append(leader_token)
	args.append("--capacity")
	args.append(str(capacity))

	pid = OS.create_process(executable, args, false)
	if pid <= 0:
		push_error("ServerProcess: failed to launch headless server for room '%s'" % room_id)
		return FAILED
	return OK


## Terminates the spawned process if it is still alive. Safe to call at any time.
func kill() -> void:
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	pid = -1
