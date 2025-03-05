# autoload/events.gd
# Autoloaded singleton for game-wide event management
# Add this script as an autoload named "event" in Project Settings
extends Node

# === PLAYER EVENTS ===
@warning_ignore("unused_signal")
signal player_position_changed(position)
@warning_ignore("unused_signal")
signal player_damaged(amount, source)
@warning_ignore("unused_signal")
signal player_died
@warning_ignore("unused_signal")
signal player_respawned(position)

# === GAMEPLAY EVENTS ===
@warning_ignore("unused_signal")
signal game_started
@warning_ignore("unused_signal")
signal game_paused
@warning_ignore("unused_signal")
signal game_resumed
@warning_ignore("unused_signal")
signal game_over
@warning_ignore("unused_signal")
signal game_restarted

# === ENTITY EVENTS ===
@warning_ignore("unused_signal")
signal entity_spawned(entity, entity_type)
@warning_ignore("unused_signal")
signal entity_despawned(entity, entity_type)
@warning_ignore("unused_signal")
signal enemy_destroyed(enemy, destroyer)
@warning_ignore("unused_signal")
signal asteroid_mined(asteroid, player)

# === RESOURCE EVENTS ===
@warning_ignore("unused_signal")
signal credits_changed(new_amount)
@warning_ignore("unused_signal")
signal resource_collected(resource_id, amount)
@warning_ignore("unused_signal")
signal trade_completed(station, resources_bought, resources_sold, total_cost)

# === UPGRADE EVENTS ===
@warning_ignore("unused_signal")
signal upgrade_purchased(upgrade, component, cost)
@warning_ignore("unused_signal")
signal upgrade_removed(upgrade, component)

# === UI EVENTS ===
@warning_ignore("unused_signal")
signal ui_opened(ui_type)
@warning_ignore("unused_signal")
signal ui_closed(ui_type)

# === HELPER METHODS ===

# Safe connect helper with type checking
func safe_connect(signal_name: StringName, callable: Callable) -> void:
	if not has_signal(signal_name):
		push_warning("Events: Trying to connect to nonexistent signal '%s'" % signal_name)
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
		push_warning("Events: Trying to emit nonexistent signal '%s'" % signal_name)
		return
	
	match args.size():
		0: emit_signal(signal_name)
		1: emit_signal(signal_name, args[0])
		2: emit_signal(signal_name, args[0], args[1])
		3: emit_signal(signal_name, args[0], args[1], args[2])
		4: emit_signal(signal_name, args[0], args[1], args[2], args[3])
		_: 
			if args.size() > 4:
				push_warning("Events: Too many arguments for signal '%s'" % signal_name)
				emit_signal(signal_name, args[0], args[1], args[2], args[3])
			else:
				emit_signal(signal_name)

# === OPTIONAL: DYNAMIC EVENTS ===
# Uncomment if you need to add signals at runtime

#var _dynamic_signals: Array = []
#
#func add_dynamic_signal(signal_name: String) -> void:
#	if has_signal(signal_name) or _dynamic_signals.has(signal_name):
#		return
#		
#	add_user_signal(signal_name)
#	_dynamic_signals.append(signal_name)
#
#func remove_dynamic_signal(signal_name: String) -> void:
#	if not _dynamic_signals.has(signal_name):
#		return
#		
#	# This is a bit of a hack, but Godot doesn't have a way to remove signals
#	# Just disconnect everything from it
#	var connections = get_signal_connection_list(signal_name)
#	for connection in connections:
#		disconnect(signal_name, connection["callable"])
#		
#	_dynamic_signals.erase(signal_name)
