extends Node
class_name InputPropagator

## Class for generating Input maps for local multiplayer. 
## 
## - Create `px_YOUR_ACTION_HERE` formatted actions with whatever controller device id
## - Call `generate_player_inputs()` to create px_ -> p1, p2, p3... versions of each action
##     with incrementing device ids (0, 1, 2...).
##
## E.g.
## InputPropagator.new().generate_player_inputs()

## Generates player_count versions of actions with prefix "px_". 
## E.g. px_left -> p1_left, p2_left, p3_left with different device ids.
func generate_player_inputs(player_count: int = 4):
	var input_map = InputMap
	
	# Get all existing input actions
	var all_actions = input_map.get_actions()
	var px_actions = []
	
	# Find all actions with "px_" prefix
	for action in all_actions:
		if action.begins_with("px_"):
			px_actions.append(action)
	
	# Generate player-specific actions for each px_ action
	for px_action in px_actions:
		var base_action_name = px_action.substr(3)  # Remove "px_" prefix
		
		# Get all events from the px_ action
		var px_events = input_map.action_get_events(px_action)
		
		# Create player-specific actions
		for player_id in range(1, player_count + 1):
			var player_action_name = "p" + str(player_id) + "_" + base_action_name
			
			# Add the new action if it doesn't exist
			if not input_map.has_action(player_action_name):
				input_map.add_action(player_action_name)
			else:
				# Clear existing events to rebuild
				input_map.action_erase_events(player_action_name)
			
			# Copy and modify events for this player
			for event in px_events:
				var new_event = event.duplicate()
				
				# Handle different input event types
				if event is InputEventJoypadButton:
					new_event.device = player_id - 1  # Device 0 for player 1, etc.
				elif event is InputEventJoypadMotion:
					new_event.device = player_id - 1
				elif event is InputEventKey:
					if player_id != 1:
						# Only assign the template mouse/kb input to p1 for debugging
						continue
				elif event is InputEventMouseButton:
					if player_id != 1:
						# Only assign the template mouse/kb input to p1 for debugging
						continue
				elif event is InputEventMouseMotion:
					if player_id != 1:
						# Only assign the template mouse/kb input to p1 for debugging
						continue
				
				# Add the modified event to the player's action
				input_map.action_add_event(player_action_name, new_event)
		
		print("Generated player inputs for: ", px_action, " -> ", player_count, " players")
	
	print("Player input generation complete!")
