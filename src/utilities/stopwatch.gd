extends RefCounted
class_name Stopwatch

## A simple utility for measuring elapsed time in milliseconds.
##
## Tracks time elapsed since instantiation or the last reset using system ticks.

## The timestamp in milliseconds when the stopwatch was started or restarted.
var start_time_ms: int


func _init() -> void:
	start_time_ms = Time.get_ticks_msec()


## Returns the elapsed time in milliseconds since the stopwatch started.
func measure() -> int:
	return Time.get_ticks_msec() - start_time_ms


## Resets the start time to the current system tick.
func restart() -> void:
	start_time_ms = Time.get_ticks_msec()


## Returns the elapsed time in milliseconds, then resets the stopwatch.
func measure_and_restart() -> int:
	var ms := measure()
	restart()
	return ms


## Pushes a warning message to the Godot debugger with the elapsed time.
func log(prefix_msg: String = "Stopwatch") -> void:
	push_warning(prefix_msg, ": %sms passed (%.2fs)" % [measure(), measure() * 0.001])


func _to_string() -> String:
	return "Stopwatch: %sms passed (%.2fs)" % [measure(), measure() * 0.001]
