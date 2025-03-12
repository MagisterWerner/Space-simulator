# scripts/states/state_machine.gd - Optimized state machine with transition validation
extends Node
class_name StateMachine

signal state_changed(from_state, to_state)
signal transition_failed(from_state, to_state, reason)

@export var initial_state: NodePath
@export var debug_mode: bool = false
@export var history_size: int = 10

var current_state: State
var states: Dictionary = {}
var history: Array = []
var last_transition_time: float = 0.0
var transition_lock: bool = false
const MIN_TRANSITION_INTERVAL: float = 0.05

# Valid transitions map - override in derived state machines
var valid_transitions: Dictionary = {"*": ["*"]}  # Default: allow any transition

func _ready() -> void:
	await owner.ready
	_register_states()
	_set_initial_state()

func _register_states() -> void:
	for child in get_children():
		if not child is State:
			continue
			
		# Register state with simplified naming
		var base_name = child.name.to_lower()
		if base_name.ends_with("state"):
			base_name = base_name.substr(0, base_name.length() - 5)
			
		states[child.name] = child
		states[base_name] = child
		child.state_machine = self
		
		if debug_mode:
			print("[StateMachine:%s] Registered state: %s" % [owner.name, child.name])

func _set_initial_state() -> void:
	var initial = null
	
	if not initial_state.is_empty():
		initial = get_node(initial_state)
		if not initial is State:
			push_error("Initial state is not a State node")
			initial = null
	
	if not initial and not states.is_empty():
		initial = states.values()[0]
	
	if initial:
		current_state = initial
		current_state.enter()
		if debug_mode:
			print("[StateMachine:%s] Initial state: %s" % [owner.name, current_state.name])
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

func can_transition(from_state_name: String, to_state_name: String) -> bool:
	# Fast path for unrestricted transitions (default case)
	if valid_transitions.is_empty() or (valid_transitions.has("*") and valid_transitions["*"].has("*")):
		return true
	
	# Check specific from→to transitions
	if valid_transitions.has(from_state_name):
		if valid_transitions[from_state_name].has(to_state_name) or valid_transitions[from_state_name].has("*"):
			return true
	
	# Check wildcard transitions
	if valid_transitions.has("*") and valid_transitions["*"].has(to_state_name):
		return true
	
	return false

func transition_to(target_state_name: String, params: Dictionary = {}) -> bool:
	# Fast validation checks
	if target_state_name.is_empty() or transition_lock:
		return false
	
	if not states.has(target_state_name):
		var from_state_name = current_state.name if current_state else ""
		transition_failed.emit(from_state_name, target_state_name, "state_not_found")
		return false
	
	var to_state = states[target_state_name]
	if current_state == to_state:
		return false
	
	# Apply rate limiting
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_transition_time < MIN_TRANSITION_INTERVAL:
		return false
	
	# Validate transition based on rules
	var from_state_name = current_state.name if current_state else ""
	if not can_transition(from_state_name, to_state.name):
		transition_failed.emit(from_state_name, to_state.name, "invalid_transition")
		return false
	
	# Lock transitions
	transition_lock = true
	last_transition_time = current_time
	
	var from_state = current_state
	
	# Exit current state
	if from_state:
		if debug_mode:
			print("[StateMachine:%s] Exiting state: %s" % [owner.name, from_state.name])
		from_state.exit()
		history.append(from_state.name)
		# Keep history within limit
		if history.size() > history_size:
			history.pop_front()
	
	# Enter new state
	current_state = to_state
	current_state.enter(params)
	
	# Emit signals
	state_changed.emit(from_state_name, current_state.name)
	
	# Unlock transitions
	transition_lock = false
	
	return true

# Transition back to previous state
func transition_back(params: Dictionary = {}) -> bool:
	if history.is_empty():
		return false
	
	return transition_to(history.pop_back(), params)

# Get current state name
func get_current_state_name() -> String:
	return current_state.name if current_state else ""

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
		if debug_mode:
			print("[StateMachine:%s] Reset to initial state: %s" % [owner.name, current_state.name])

# Define transition rules
func set_valid_transitions(rules: Dictionary) -> void:
	valid_transitions = rules
