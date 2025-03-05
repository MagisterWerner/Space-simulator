# event_system.gd
extends Node
class_name EventSystem

# Event system that uses signals for communication between different parts of the game
# This avoids tight coupling between systems

# Dictionary to store all registered signals
# event_name -> Signal
var _events: Dictionary = {}

# Dictionary to store methods connected to signals
# event_name -> Array of Callables
var _connections: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # Keep processing during pause

# Register a new event
func register_event(event_name: String) -> void:
	if _events.has(event_name):
		push_warning("EventSystem: Event '%s' is already registered" % event_name)
		return
	
	# Create a new signal for this event
	_events[event_name] = Signal()
	_connections[event_name] = []

# Connect a method to an event
func connect_event(event_name: String, callable: Callable) -> void:
	if not _events.has(event_name):
		# Auto-register the event if it doesn't exist
		register_event(event_name)
	
	var signal_ref: Signal = _events[event_name]
	
	# Avoid connecting the same method multiple times
	if not signal_ref.is_connected(callable):
		signal_ref.connect(callable)
		_connections[event_name].append(callable)

# Disconnect a method from an event
func disconnect_event(event_name: String, callable: Callable) -> void:
	if not _events.has(event_name):
		push_warning("EventSystem: Event '%s' doesn't exist" % event_name)
		return
	
	var signal_ref: Signal = _events[event_name]
	
	if signal_ref.is_connected(callable):
		signal_ref.disconnect(callable)
		_connections[event_name].erase(callable)

# Emit an event with optional arguments
func emit_event(event_name: String, args: Array = []) -> void:
	if not _events.has(event_name):
		# Auto-register the event if it doesn't exist
		register_event(event_name)
	
	var signal_ref: Signal = _events[event_name]
	
	# Emit the signal with the provided arguments
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
			push_warning("EventSystem: Too many arguments for event '%s'" % event_name)
			# Emit with up to 4 arguments
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
	if not _connections.has(event_name):
		return 0
	return _connections[event_name].size()

# Remove all connections for an event
func clear_event_connections(event_name: String) -> void:
	if not _events.has(event_name):
		return
	
	var signal_ref: Signal = _events[event_name]
	
	# Disconnect all connected methods
	for callable in _connections[event_name]:
		if signal_ref.is_connected(callable):
			signal_ref.disconnect(callable)
	
	_connections[event_name].clear()

# Remove an event completely
func remove_event(event_name: String) -> void:
	if not _events.has(event_name):
		return
	
	# First clear all connections
	clear_event_connections(event_name)
	
	# Then remove the event
	_events.erase(event_name)
	_connections.erase(event_name)

# Clear all events and connections
func clear_all_events() -> void:
	for event_name in _events.keys():
		remove_event(event_name)

# Example usage:
# In a global autoload:
# var events = EventSystem.new()
# add_child(events)
# events.register_event("player_died")
# events.connect_event("player_died", Callable(self, "_on_player_died"))
# ...
# events.emit_event("player_died", [player_node])
#
# To receive events:
# func _on_player_died(player_node) -> void:
#     print("Player died: ", player_node.name)
