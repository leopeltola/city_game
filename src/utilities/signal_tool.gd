class_name SignalTool
extends RefCounted

## Awaits until ANY of the provided signals are emitted.
## Returns the signal that was emitted first.
static func any(signals: Array[Signal]) -> Signal:
	var triggered_signal: Dictionary = { "ref": null }
	var handlers: Array[Callable] = []

	for s in signals:
		# We must bind 's' to the lambda to ensure we capture the correct signal
		# for this specific iteration.
		var handler = (func(emitted_signal): triggered_signal.ref = emitted_signal).bind(s)

		# store the callable so we can disconnect it later
		handlers.append(handler)
		s.connect(handler) # cleanup is manual later

	while triggered_signal.ref == null:
		await Engine.get_main_loop().process_frame

	# This ensures we don't leave dangling connections on the signals that didn't win.
	for i in range(signals.size()):
		var s = signals[i]
		var handler = handlers[i]
		if s.is_connected(handler):
			s.disconnect(handler)

	return triggered_signal.ref


## Awaits until ALL of the provided signals have been emitted at least once.
static func all(signals: Array[Signal]) -> void:
	if signals.is_empty():
		return

	# Track how many signals are left to fire
	var state = { "remaining": signals.size() }

	for s in signals:
		s.connect(func(): state.remaining -= 1, CONNECT_ONE_SHOT)

	while state.remaining > 0:
		await Engine.get_main_loop().process_frame
