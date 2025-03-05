# scripts/states/state_machine.gd - Improved state machine with transition validation

extends Node
class_name StateMachine

signal state_changed(from_state, to_state)
signal transition_failed(from_state, to_state, reason)

@export var initial_state: NodePath
@export var debug_mode: bool = false
@export var history_size: int = 10  # Maximum number of states to keep in history

var current_state: State
var states: Dictionary = {}
var history: Array = []
var last_transition_time: float = 0.0
var transition_lock: bool = false  # Prevents simultaneous transitions
const MIN_TRANSITION_INTERVAL: float = 0.05  # 50ms minimum between transitions

# Valid transitions - override in derived state machines
var valid_transitions: Dictionary = {
	# Format: "from_state": ["to_state1", "to_state2", ...],
	# Use "*" as a wildcard to allow transition from/to any state
	"*": ["*"]  # Default: allow any transition
}

func _ready() -> void:
	await owner.ready
	
	# Get all child states
	for child in get_children():
		if child is State:
			# Register state with multiple names for flexibility
			var name_lower = child.name.to_lower()
			states[child.name] = child            # Original name: "IdleState"
			states[name_lower] = child            # Lowercase: "idlestate"
			
			# Also register without "State" suffix for convenience
			if name_lower.ends_with("state"):
				var base_name = name_lower.substr(0, name_lower.length() - 5)  # Remove "state"
				states[base_name] = child         # Base name: "idle"
			
			child.state_machine = self
			debug_print("Registered state: %s (also accessible via '%s')" % [child.name, name_lower.replace("state", "")])
	
	# Set initial state
	if not initial_state.is_empty():
		var initial = get_node(initial_state)
		if initial is State:
			current_state = initial
		else:
			push_error("Initial state is not a State node")
	elif not states.is_empty():
		# Default to first state
		current_state = states.values()[0]
	
	if current_state:
		current_state.enter()
		debug_print("Initial state: %s" % current_state.name)
	else:
		push_error("No initial state set and no states found in children")

func _process(delta: float) -> void:
	if current_state:
		current_state.update(delta)

func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_update(delta)

func _unhandled_input(event: InputEvent) -> void:
	if current_state:
		current_state.handle_input(event)

# Check if a transition is valid based on rules
func can_transition(from_state_name: String, to_state_name: String) -> bool:
	# If transition rules are empty, allow all transitions
	if valid_transitions.is_empty():
		return true
	
	# Allow if wildcard is used
	if valid_transitions.has("*") and valid_transitions["*"].has("*"):
		return true
	
	# Check specific from→to transitions
	if valid_transitions.has(from_state_name):
		if valid_transitions[from_state_name].has(to_state_name) or valid_transitions[from_state_name].has("*"):
			return true
	
	# Check wildcard from→specific to
	if valid_transitions.has("*"):
		if valid_transitions["*"].has(to_state_name):
			return true
	
	# Check specific from→wildcard to
	if valid_transitions.has(from_state_name):
		if valid_transitions[from_state_name].has("*"):
			return true
	
	return false

func transition_to(target_state_name: String, params: Dictionary = {}) -> bool:
	# Protect against empty target
	if target_state_name.is_empty():
		debug_print("Cannot transition to empty state name")
		return false
	
	# Check if state exists
	if not states.has(target_state_name):
		var error_msg = "State '%s' not found. Available states: %s" % [target_state_name, states.keys()]
		push_error("StateMachine: " + error_msg)
		
		# Safe handling of current_state.name
		var current_state_name = ""
		if current_state:
			current_state_name = current_state.name
			
		transition_failed.emit(current_state_name, target_state_name, "state_not_found")
		return false
	
	var to_state = states[target_state_name]
	
	# Don't transition if we're already in this state
	if current_state == to_state:
		debug_print("Already in state: %s" % target_state_name)
		return false
	
	# Prevent multiple transitions at once
	if transition_lock:
		debug_print("Transition locked - another transition in progress")
		return false
	
	# Apply rate limiting
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_transition_time < MIN_TRANSITION_INTERVAL:
		debug_print("Transition rate limited - too soon after previous transition")
		return false
	
	# Validate transition based on rules
	var from_state_name = ""
	if current_state:
		from_state_name = current_state.name
		
	if not can_transition(from_state_name, to_state.name):
		var error_msg = "Invalid transition from '%s' to '%s'" % [from_state_name, to_state.name]
		debug_print(error_msg)
		transition_failed.emit(from_state_name, to_state.name, "invalid_transition")
		return false
	
	# Lock transitions
	transition_lock = true
	last_transition_time = current_time
	
	var from_state = current_state
	
	# Exit current state
	if from_state:
		debug_print("Exiting state: %s" % from_state.name)
		from_state.exit()
		history.append(from_state.name)
		# Keep history within size limit
		while history.size() > history_size:
			history.pop_front()
	
	# Enter new state
	current_state = to_state
	debug_print("Entering state: %s" % current_state.name)
	current_state.enter(params)
	
	# Emit signals
	var from_state_name_safe = ""
	if from_state:
		from_state_name_safe = from_state.name
	
	state_changed.emit(from_state_name_safe, current_state.name)
	
	# Log the transition
	if from_state:
		debug_print("Transitioned from %s to %s" % [from_state.name, current_state.name])
	else:
		debug_print("Transitioned from null to %s" % current_state.name)
	
	# Unlock transitions
	transition_lock = false
	
	return true

# Transition back to previous state
func transition_back(params: Dictionary = {}) -> bool:
	if history.is_empty():
		debug_print("Cannot transition back - no history")
		return false
	
	var prev_state = history.pop_back()
	return transition_to(prev_state, params)

# Get current state name
func get_current_state_name() -> String:
	if current_state:
		return current_state.name
	return ""

# Reset state machine to initial state
func reset() -> void:
	history.clear()
	
	var initial = null
	if not initial_state.is_empty():
		initial = get_node(initial_state)
	elif not states.is_empty():
		initial = states.values()[0]
	
	if initial and initial != current_state:
		if current_state:
			current_state.exit()
		current_state = initial
		current_state.enter()
		debug_print("Reset to initial state: %s" % current_state.name)

# Debug output
func debug_print(message: String) -> void:
	if debug_mode:
		print("[StateMachine:%s] %s" % [owner.name, message])

# Define transition rules
func set_valid_transitions(rules: Dictionary) -> void:
	valid_transitions = rules
