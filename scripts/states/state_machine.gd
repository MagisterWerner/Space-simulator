# scripts/states/state_machine.gd - Optimized state machine with transition validation
extends Node
class_name StateMachine

signal state_changed(from_state, to_state)
signal transition_failed(from_state, to_state, reason)

@export var initial_state: NodePath
@export var debug_mode: bool = false
@export var history_size: int = 10

# State references
var current_state: State
var previous_state: State

# State cache for faster lookups
var _state_cache = {}
var _transition_cache = {}

# Optimized history tracking with circular buffer
var _history = []
var _history_index = 0

# Transition throttling for performance
var _last_transition_time: float = 0.0
var _transition_lock: bool = false
const MIN_TRANSITION_INTERVAL: float = 0.05

# Valid transitions map with faster string key format
var _valid_transitions = {}
var _wildcard_from_transitions = []
var _wildcard_to_transitions = {}
var _any_to_any = false

func _ready() -> void:
	await owner.ready
	_register_states()
	_set_initial_state()
	_build_transition_tables()

func _register_states() -> void:
	for child in get_children():
		if not child is State:
			continue
		
		# Register state with multiple access paths
		var state_name = child.name
		_state_cache[state_name] = child
		
		# Also register simplified names without "State" suffix
		var base_name = state_name.to_lower()
		if base_name.ends_with("state"):
			base_name = base_name.substr(0, base_name.length() - 5)
			_state_cache[base_name] = child
		
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
	
	if not initial and not _state_cache.is_empty():
		initial = _state_cache.values()[0]
	
	if initial:
		current_state = initial
		previous_state = initial
		current_state.enter()
		
		if debug_mode:
			print("[StateMachine:%s] Initial state: %s" % [owner.name, current_state.name])
	else:
		push_error("No initial state set and no states found in children")

func _build_transition_tables() -> void:
	# Convert valid_transitions to optimized format if defined in child class
	if has_method("_define_transitions"):
		var transitions = call("_define_transitions")
		if transitions is Dictionary:
			_process_transition_rules(transitions)
	else:
		# Default: allow any transition (most flexible)
		_any_to_any = true

func _process_transition_rules(rules: Dictionary) -> void:
	_valid_transitions.clear()
	_wildcard_from_transitions.clear()
	_wildcard_to_transitions.clear()
	_any_to_any = false
	
	# Check for wildcard rule that allows anything
	if rules.has("*") and "*" in rules["*"]:
		_any_to_any = true
		return
	
	# Process all other rules
	for from_state in rules:
		var to_states = rules[from_state]
		
		if from_state == "*":
			# Wildcard source - allow to specific destinations
			_wildcard_from_transitions = to_states
			continue
		
		# Regular transition rules
		for to_state in to_states:
			if to_state == "*":
				# Allow this source to go to anything
				if not _wildcard_to_transitions.has(from_state):
					_wildcard_to_transitions[from_state] = true
			else:
				# Specific from->to transition
				var key = from_state + "->" + to_state
				_valid_transitions[key] = true

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
	# Fastest check first
	if _any_to_any:
		return true
	
	# Check transition cache
	var cache_key = from_state_name + "->" + to_state_name
	if _transition_cache.has(cache_key):
		return _transition_cache[cache_key]
	
	# Check specific from→to transitions
	var is_valid = _valid_transitions.has(cache_key)
	
	# Check wildcard to transitions ("from" can go anywhere)
	if not is_valid and _wildcard_to_transitions.has(from_state_name):
		is_valid = true
	
	# Check if "to" is in wildcard destinations (anything can go "to")
	if not is_valid and to_state_name in _wildcard_from_transitions:
		is_valid = true
	
	# Cache result
	_transition_cache[cache_key] = is_valid
	return is_valid

func transition_to(target_state_name: String, params: Dictionary = {}) -> bool:
	# Fast validation checks
	if target_state_name.is_empty() or _transition_lock:
		return false
	
	# Check state exists and retrieve from cache
	var to_state = _state_cache.get(target_state_name)
	if not to_state:
		var from_state_name = current_state.name if current_state else ""
		transition_failed.emit(from_state_name, target_state_name, "state_not_found")
		return false
	
	if current_state == to_state:
		return false
	
	# Apply rate limiting
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - _last_transition_time < MIN_TRANSITION_INTERVAL:
		return false
	
	# Validate transition based on rules
	var from_state_name = current_state.name
	if not can_transition(from_state_name, to_state.name):
		transition_failed.emit(from_state_name, to_state.name, "invalid_transition")
		return false
	
	# Lock transitions
	_transition_lock = true
	_last_transition_time = current_time
	
	# Record current state before changing
	previous_state = current_state
	
	# Exit current state
	if current_state and debug_mode:
		print("[StateMachine:%s] Exiting state: %s" % [owner.name, current_state.name])
	
	current_state.exit()
	
	# Update history with circular buffer
	if history_size > 0:
		if _history.size() < history_size:
			_history.append(current_state.name)
		else:
			_history[_history_index] = current_state.name
			_history_index = (_history_index + 1) % history_size
	
	# Enter new state
	current_state = to_state
	
	if debug_mode:
		print("[StateMachine:%s] Entering state: %s" % [owner.name, current_state.name])
	
	current_state.enter(params)
	
	# Emit signals
	state_changed.emit(from_state_name, current_state.name)
	
	# Unlock transitions
	_transition_lock = false
	
	return true

# Transition back to previous state
func transition_back(params: Dictionary = {}) -> bool:
	if not previous_state or previous_state == current_state:
		return false
		
	return transition_to(previous_state.name, params)

# Transition to most recent history state
func transition_to_history(params: Dictionary = {}) -> bool:
	if _history.is_empty():
		return false
	
	var last_index = (_history_index - 1 + _history.size()) % _history.size()
	var last_state = _history[last_index]
	_history.remove_at(last_index)
	
	if _history_index > 0:
		_history_index -= 1
	
	return transition_to(last_state, params)

# Get current state name
func get_current_state_name() -> String:
	return current_state.name if current_state else ""

# Reset state machine to initial state
func reset() -> void:
	_history.clear()
	_history_index = 0
	
	var initial = null
	if not initial_state.is_empty():
		initial = get_node(initial_state)
	elif not _state_cache.is_empty():
		initial = _state_cache.values()[0]
	
	if initial and initial != current_state:
		if current_state:
			current_state.exit()
		current_state = initial
		previous_state = initial
		current_state.enter()
		
		if debug_mode:
			print("[StateMachine:%s] Reset to initial state: %s" % [owner.name, current_state.name])

# Define transition rules (override in subclasses)
func _define_transitions() -> Dictionary:
	return {"*": ["*"]}  # Default: allow any transition

# Check if in specific state
func is_in_state(state_name: String) -> bool:
	if not current_state:
		return false
		
	if state_name == current_state.name:
		return true
		
	# Also check simplified name
	var check_name = state_name.to_lower()
	var current_name = current_state.name.to_lower()
	
	if current_name.ends_with("state"):
		current_name = current_name.substr(0, current_name.length() - 5)
	
	return check_name == current_name
