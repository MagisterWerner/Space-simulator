# autoload/event_manager.gd
#
# Events Manager Singleton
# ===============
# Purpose:
#   Provides a centralized event bus for game-wide communication.
#   Decouples systems by allowing them to communicate without direct references.
extends Node

# === PLAYER EVENTS ===
signal player_position_changed(position)
signal player_damaged(amount, source)
signal player_died
signal player_respawned(position)

# === GAMEPLAY EVENTS ===
signal game_started
signal game_paused
signal game_resumed
signal game_over
signal game_restarted

# === ENTITY EVENTS ===
signal entity_spawned(entity, entity_type)
signal entity_despawned(entity, entity_type)
signal enemy_destroyed(enemy, destroyer)
signal asteroid_mined(asteroid, player)

# === RESOURCE EVENTS ===
signal credits_changed(new_amount)
signal resource_collected(resource_id, amount)
signal trade_completed(station, resources_bought, resources_sold, total_cost)

# === UPGRADE EVENTS ===
signal upgrade_purchased(upgrade, component, cost)
signal upgrade_removed(upgrade, component)

# === UI EVENTS ===
signal ui_opened(ui_type)
signal ui_closed(ui_type)

# === HELPER METHODS ===

# Safe connect helper with type checking
func safe_connect(signal_name: StringName, callable: Callable) -> void:
	if not has_signal(signal_name):
		push_warning("EventManager: Trying to connect to nonexistent signal '%s'" % signal_name)
		return
		
	connect(signal_name, callable)

# Safe disconnect helper
func safe_disconnect(signal_name: StringName, callable: Callable) -> void:
	if not has_signal(signal_name):
		return
		
	if is_connected(signal_name, callable):
		disconnect(signal_name, callable)

# Safe emit helper with type checking
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

# === DYNAMIC EVENTS ===
# For adding signals at runtime

var _dynamic_signals: Array = []

func add_dynamic_signal(signal_name: String) -> void:
	if has_signal(signal_name) or _dynamic_signals.has(signal_name):
		return
		
	add_user_signal(signal_name)
	_dynamic_signals.append(signal_name)

func remove_dynamic_signal(signal_name: String) -> void:
	if not _dynamic_signals.has(signal_name):
		return
		
	# This is a bit of a hack, but Godot doesn't have a way to remove signals
	# Just disconnect everything from it
	var connections = get_signal_connection_list(signal_name)
	for connection in connections:
		disconnect(signal_name, connection["callable"])
		
	_dynamic_signals.erase(signal_name)
