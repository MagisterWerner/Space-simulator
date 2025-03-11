# autoload/event_manager.gd
# Event Manager refactored with dependency injection

@tool # Enable tool mode
@warning_ignore("unused_signal") # Suppress unused signal warnings - normal for event buses

extends "res://autoload/base_service.gd"

# === PLAYER EVENTS ===
## Emitted when player position changes significantly
@warning_ignore("unused_signal")
signal player_position_changed(position)
## Emitted when player takes damage
@warning_ignore("unused_signal")
signal player_damaged(amount, source)
## Emitted when player health reaches zero
@warning_ignore("unused_signal")
signal player_died
## Emitted when player respawns after death
@warning_ignore("unused_signal")
signal player_respawned(position)

# === GAMEPLAY EVENTS ===
## Emitted when a new game is started
@warning_ignore("unused_signal")
signal game_started
## Emitted when game is paused
@warning_ignore("unused_signal")
signal game_paused
## Emitted when game is resumed from pause
@warning_ignore("unused_signal")
signal game_resumed
## Emitted when game is over (player lost)
@warning_ignore("unused_signal")
signal game_over
## Emitted when game is restarted
@warning_ignore("unused_signal")
signal game_restarted

# === ENTITY EVENTS ===
## Emitted when a new entity is created in the game
@warning_ignore("unused_signal")
signal entity_spawned(entity, entity_type)
## Emitted when an entity is removed from the game
@warning_ignore("unused_signal")
signal entity_despawned(entity, entity_type)
## Emitted when an enemy is destroyed
@warning_ignore("unused_signal")
signal enemy_destroyed(enemy, destroyer)
## Emitted when an asteroid is successfully mined
@warning_ignore("unused_signal")
signal asteroid_mined(asteroid, player)

# === RESOURCE EVENTS ===
## Emitted when player credits amount changes
@warning_ignore("unused_signal")
signal credits_changed(new_amount)
## Emitted when player collects a resource
@warning_ignore("unused_signal")
signal resource_collected(resource_id, amount)
## Emitted when a trade is completed at a station
@warning_ignore("unused_signal")
signal trade_completed(station, resources_bought, resources_sold, total_cost)

# === UPGRADE EVENTS ===
## Emitted when an upgrade is purchased and applied
@warning_ignore("unused_signal")
signal upgrade_purchased(upgrade, component, cost)
## Emitted when an upgrade is removed from a component
@warning_ignore("unused_signal")
signal upgrade_removed(upgrade, component)

# === UI EVENTS ===
## Emitted when a UI screen/panel is opened
@warning_ignore("unused_signal")
signal ui_opened(ui_type)
## Emitted when a UI screen/panel is closed
@warning_ignore("unused_signal")
signal ui_closed(ui_type)

# === DYNAMIC EVENTS ===
# Stores dynamically created signals
var _dynamic_signals: Array = []

func _ready() -> void:
	# Register self with ServiceLocator
	call_deferred("register_self")
	
	# Configure process mode to continue during pause
	process_mode = Node.PROCESS_MODE_ALWAYS

# Return dependencies required by this service
func get_dependencies() -> Array:
	return [] # EventManager has no required dependencies

# Initialize this service
func initialize_service() -> void:
	if OS.is_debug_build():
		print("EventManager: Initialized successfully")
	
	# Mark as initialized
	_service_initialized = true

# === HELPER METHODS ===

## Safe connect helper with type checking.
## Prevents connecting to non-existent signals.
func safe_connect(signal_name: StringName, callable: Callable) -> void:
	if not has_signal(signal_name):
		push_warning("EventManager: Trying to connect to nonexistent signal '%s'" % signal_name)
		return
		
	if not is_connected(signal_name, callable):
		connect(signal_name, callable)

## Safe disconnect helper.
## Prevents disconnecting from non-existent signals.
func safe_disconnect(signal_name: StringName, callable: Callable) -> void:
	if not has_signal(signal_name):
		return
		
	if is_connected(signal_name, callable):
		disconnect(signal_name, callable)

## Safe emit helper with type checking.
## Validates signal exists before emitting.
func safe_emit(signal_name: StringName, args: Array = []) -> void:
	if not has_signal(signal_name):
		push_warning("EventManager: Trying to emit nonexistent signal '%s'" % signal_name)
		return
	
	match args.size():
		0: emit_signal(signal_name)
		1: emit_signal(signal_name, args[0])
		2: emit_signal(signal_name, args[0], args[1])
		3: emit_signal(signal_name, args[0], args[1], args[2])
		4: emit_signal(signal_name, args[0], args[1], args[2], args[3])
		_: 
			if args.size() > 4:
				push_warning("EventManager: Too many arguments for signal '%s'" % signal_name)
				emit_signal(signal_name, args[0], args[1], args[2], args[3])
			else:
				emit_signal(signal_name)

## Adds a dynamic signal at runtime
func add_dynamic_signal(signal_name: String) -> void:
	if has_signal(signal_name) or _dynamic_signals.has(signal_name):
		return
		
	add_user_signal(signal_name)
	_dynamic_signals.append(signal_name)

## Removes a dynamic signal
func remove_dynamic_signal(signal_name: String) -> void:
	if not _dynamic_signals.has(signal_name):
		return
		
	# Disconnect all connections from this signal
	var connections = get_signal_connection_list(signal_name)
	for connection in connections:
		disconnect(signal_name, connection["callable"])
		
	_dynamic_signals.erase(signal_name)

## Check if a dynamic signal exists
func has_dynamic_signal(signal_name: String) -> bool:
	return _dynamic_signals.has(signal_name)

## Emits a signal if possible, otherwise adds and emits
func emit_or_create(signal_name: String, args: Array = []) -> void:
	if not has_signal(signal_name) and not has_dynamic_signal(signal_name):
		add_dynamic_signal(signal_name)
	
	safe_emit(signal_name, args)

## Gets all signal connections for debugging
func get_all_connections() -> Dictionary:
	var result = {}
	
	# Get all signals
	var signals = get_signal_list()
	for sig in signals:
		var connections = get_signal_connection_list(sig.name)
		if connections.size() > 0:
			result[sig.name] = connections
	
	# Add dynamic signals
	for sig in _dynamic_signals:
		var connections = get_signal_connection_list(sig)
		if connections.size() > 0:
			result[sig] = connections
			
	return result
