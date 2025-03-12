@tool
extends Node

# PLAYER EVENTS
signal player_position_changed(position)
signal player_damaged(amount, source)
signal player_died
signal player_respawned(position)

# GAMEPLAY EVENTS
signal game_started
signal game_paused
signal game_resumed
signal game_over
signal game_restarted

# ENTITY EVENTS
signal entity_spawned(entity, entity_type)
signal entity_despawned(entity, entity_type)
signal enemy_destroyed(enemy, destroyer)
signal asteroid_mined(asteroid, player)

# RESOURCE EVENTS
signal credits_changed(new_amount)
signal resource_collected(resource_id, amount)
signal trade_completed(station, resources_bought, resources_sold, total_cost)

# UPGRADE EVENTS
signal upgrade_purchased(upgrade, component, cost)
signal upgrade_removed(upgrade, component)

# UI EVENTS
signal ui_opened(ui_type)
signal ui_closed(ui_type)

# Dynamic signals
var _dynamic_signals = []

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

# PLAYER EVENT EMITTERS

func emit_player_position_changed(position: Vector2) -> void:
	player_position_changed.emit(position)

func emit_player_damaged(amount: float, source = null) -> void:
	player_damaged.emit(amount, source)

func emit_player_died() -> void:
	player_died.emit()

func emit_player_respawned(position: Vector2) -> void:
	player_respawned.emit(position)

# GAMEPLAY EVENT EMITTERS

func emit_game_started() -> void:
	game_started.emit()

func emit_game_paused() -> void:
	game_paused.emit()

func emit_game_resumed() -> void:
	game_resumed.emit()

func emit_game_over() -> void:
	game_over.emit()

func emit_game_restarted() -> void:
	game_restarted.emit()

# ENTITY EVENT EMITTERS

func emit_entity_spawned(entity: Node, entity_type: String) -> void:
	entity_spawned.emit(entity, entity_type)

func emit_entity_despawned(entity: Node, entity_type: String) -> void:
	entity_despawned.emit(entity, entity_type)

func emit_enemy_destroyed(enemy: Node, destroyer: Node) -> void:
	enemy_destroyed.emit(enemy, destroyer)

func emit_asteroid_mined(asteroid: Node, player: Node) -> void:
	asteroid_mined.emit(asteroid, player)

# RESOURCE EVENT EMITTERS

func emit_credits_changed(new_amount: int) -> void:
	credits_changed.emit(new_amount)

func emit_resource_collected(resource_id: int, amount: int) -> void:
	resource_collected.emit(resource_id, amount)

func emit_trade_completed(station: Node, resources_bought: Dictionary, resources_sold: Dictionary, total_cost: float) -> void:
	trade_completed.emit(station, resources_bought, resources_sold, total_cost)

# UPGRADE EVENT EMITTERS

func emit_upgrade_purchased(upgrade, component, cost: float = 0.0) -> void:
	upgrade_purchased.emit(upgrade, component, cost)

func emit_upgrade_removed(upgrade, component) -> void:
	upgrade_removed.emit(upgrade, component)

# UI EVENT EMITTERS

func emit_ui_opened(ui_type: String) -> void:
	ui_opened.emit(ui_type)

func emit_ui_closed(ui_type: String) -> void:
	ui_closed.emit(ui_type)

# HELPER METHODS

# Safe connect with error checking
func safe_connect(signal_name, callable):
	if not has_signal(signal_name):
		push_warning("EventManager: Trying to connect to nonexistent signal '%s'" % signal_name)
		return
		
	if not is_connected(signal_name, callable):
		connect(signal_name, callable)

# Safe disconnect
func safe_disconnect(signal_name, callable):
	if has_signal(signal_name) and is_connected(signal_name, callable):
		disconnect(signal_name, callable)

# Safe emit with validation
func safe_emit(signal_name, args = []):
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

# Add a dynamic signal at runtime
func add_dynamic_signal(signal_name):
	if has_signal(signal_name) or _dynamic_signals.has(signal_name):
		return
		
	add_user_signal(signal_name)
	_dynamic_signals.append(signal_name)

# Remove a dynamic signal
func remove_dynamic_signal(signal_name):
	if not _dynamic_signals.has(signal_name):
		return
		
	# Disconnect all connections from this signal
	var connections = get_signal_connection_list(signal_name)
	for connection in connections:
		disconnect(signal_name, connection["callable"])
		
	_dynamic_signals.erase(signal_name)

# Check if a dynamic signal exists
func has_dynamic_signal(signal_name):
	return _dynamic_signals.has(signal_name)

# Emit or create a signal
func emit_or_create(signal_name, args = []):
	if not has_signal(signal_name) and not has_dynamic_signal(signal_name):
		add_dynamic_signal(signal_name)
	
	safe_emit(signal_name, args)

# Get all signal connections for debugging
func get_all_connections():
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
