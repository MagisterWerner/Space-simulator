# scripts/core/state_machine.gd
class_name StateMachine
extends Node

# Entity that owns this state machine
var entity = null
var current_state = null
var previous_state = null
var states = {}
var state_history = []

# Maximum size of state history (for debugging)
var max_history_size = 10

func _ready():
	# Get the entity that owns this state machine
	entity = get_parent()
	if not entity:
		push_error("StateMachine must be a child of a Node")
		return
	
	# Register all child states
	for child in get_children():
		if child.has_method("enter") and child.has_method("exit"):  # Simple check for "State-like" nodes
			states[child.name] = child
			
			# Link state to state machine
			if child.has_method("initialize"):
				child.initialize(self, entity)
			
			# We can also use setter methods if the above doesn't work
			if "state_machine" in child:
				child.state_machine = self
			if "entity" in child:
				child.entity = entity
	
	print("State machine initialized with " + str(states.size()) + " states")

func _process(delta):
	if current_state and current_state.has_method("process"):
		current_state.process(delta)

func _physics_process(delta):
	if current_state and current_state.has_method("physics_process"):
		current_state.physics_process(delta)

func _input(event):
	if current_state and current_state.has_method("handle_input"):
		current_state.handle_input(event)

# Change to a new state
func change_state(state_name):
	# Validate state exists
	if not states.has(state_name):
		push_error("Cannot change to non-existent state: " + state_name)
		return false
	
	# Exit current state if it exists
	if current_state:
		current_state.exit()
		previous_state = current_state
		
		# Add to history for debugging
		state_history.append(current_state.name)
		if state_history.size() > max_history_size:
			state_history.pop_front()
	
	# Change to new state
	current_state = states[state_name]
	print(entity.name + " changing state to: " + state_name)
	
	# Enter the new state
	current_state.enter()
	return true

# Return to the previous state if possible
func go_back_to_previous_state():
	if previous_state:
		return change_state(previous_state.name)
	return false

# Get the current state name (useful for conditional checks)
func get_current_state_name():
	if current_state:
		return current_state.name
	return ""

# Check if a state exists in this state machine
func has_state(state_name):
	return states.has(state_name)
