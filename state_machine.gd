# state_machine.gd
extends Node
class_name StateMachine

signal state_changed(from_state, to_state)

@export var initial_state: NodePath
@export var debug_mode: bool = false

var current_state: State
var states: Dictionary = {}
var history: Array = []

func _ready() -> void:
	await owner.ready
	
	# Get all child states
	for child in get_children():
		if child is State:
			# Store state with multiple name variations for flexibility
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

func transition_to(target_state_name: String, params: Dictionary = {}) -> void:
	if not states.has(target_state_name):
		push_error("State '%s' not found in StateMachine. Available states: %s" % [target_state_name, states.keys()])
		return
	
	var from_state = current_state
	var to_state = states[target_state_name]
	
	if from_state:
		from_state.exit()
		history.append(from_state.name)
		# Keep a reasonable history size
		if history.size() > 10:
			history.pop_front()
	
	current_state = to_state
	current_state.enter(params)
	
	state_changed.emit(from_state.name if from_state else "", current_state.name)
	debug_print("Transitioned from %s to %s" % [from_state.name if from_state else "null", current_state.name])

func transition_back() -> void:
	if history.is_empty():
		return
	
	var prev_state = history.pop_back()
	transition_to(prev_state)

func get_current_state_name() -> String:
	if current_state:
		return current_state.name
	return ""

func debug_print(message: String) -> void:
	if debug_mode:
		print("[StateMachine:%s] %s" % [owner.name, message])
