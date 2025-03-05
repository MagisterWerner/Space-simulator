# event_system.gd
extends Node
class_name EventSystem

# Event system that uses signals for communication between different parts of the game
# This avoids tight coupling between systems

# Dictionary to store all registered signals
# event_name -> Signal
var _events: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # Keep processing during pause

# Register a new event
func register_event(event_name: String) -> void:
	if _events.has(event_name):
		return  # Silently return if already registered
	
	# Create a new signal for this event
	_events[event_name] = Signal()

# Connect a method to an event - with better error handling
func connect_event(event_name: String, callable: Callable) -> void:
	# Make sure the event exists first
	if not _events.has(event_name):
		register_event(event_name)
	
	# Verify the callable before connecting
	if not callable.is_valid():
		push_warning("EventSystem: Cannot connect invalid callable to event '%s'" % event_name)
		return
	
	# Get the target object
	var obj = callable.get_object()
	if obj == null or not is_instance_valid(obj):
		push_warning("EventSystem: Cannot connect to null or invalid object for event '%s'" % event_name)
		return
	
	# Get the signal
	var signal_ref = _events[event_name]
	
	# Only connect if not already connected
	if not signal_ref.is_connected(callable):
		signal_ref.connect(callable)
		
		# Set up automatic disconnection when object is freed
		if not obj.tree_exiting.is_connected(_on_object_freed.bind(event_name, callable)):
			obj.tree_exiting.connect(_on_object_freed.bind(event_name, callable))

# Handle automatic disconnection when an object is freed
func _on_object_freed(event_name: String, callable: Callable) -> void:
	# Simply call disconnect_event to handle the cleanup
	disconnect_event(event_name, callable)

# Disconnect a method from an event
func disconnect_event(event_name: String, callable: Callable) -> void:
	if not _events.has(event_name):
		return
	
	var signal_ref = _events[event_name]
	
	# Only try to disconnect if connected (avoids errors)
	if signal_ref.is_connected(callable):
		signal_ref.disconnect(callable)

# Emit an event with optional arguments
func emit_event(event_name: String, args: Array = []) -> void:
	# Make sure the event exists
	if not _events.has(event_name):
		register_event(event_name)
	
	var signal_ref = _events[event_name]
	
	# Emit with the right number of arguments
	match args.size():
		0:
			signal_ref.emit()
		1:
			signal_ref.emit(args[0])
		2:
			signal_ref.emit(args[0], args[1])
		3:
			signal_ref.emit(args[0], args[1], args[2])
		4:
			signal_ref.emit(args[0], args[1], args[2], args[3])
		_:
			# Too many arguments, provide a warning and use up to 4
			push_warning("EventSystem: Too many arguments for event '%s'" % event_name)
			if args.size() > 4:
				signal_ref.emit(args[0], args[1], args[2], args[3])
			else:
				signal_ref.emit()

# Get all registered events
func get_registered_events() -> Array:
	return _events.keys()

# Check if an event is registered
func has_event(event_name: String) -> bool:
	return _events.has(event_name)

# Get the number of connections for an event
func get_connection_count(event_name: String) -> int:
	if not _events.has(event_name):
		return 0
	
	# In Godot, we don't have direct access to the number of connections
	# We could track this separately if needed
	return 0  # Placeholder

# Remove all connections for an event
func clear_event_connections(event_name: String) -> void:
	if not _events.has(event_name):
		return
	
	# Simply replace with a new signal to clear all connections
	_events[event_name] = Signal()

# Remove an event completely
func remove_event(event_name: String) -> void:
	if _events.has(event_name):
		_events.erase(event_name)

# Clear all events and connections
func clear_all_events() -> void:
	_events.clear()
