extends Node

enum LogLevel {
	VERBOSE = 0,
	DEBUG = 1,
	INFO = 2,
	WARNING = 3,
	ERROR = 4,
	NONE = 5
}

# Configuration
var enabled := OS.is_debug_build()
var log_level := LogLevel.INFO
var log_to_file := false
var log_file_path := "user://debug_log.txt"
var _log_file = null
var _game_settings = null
var _auto_id_counter := 0

# Convenience strings for log levels
const LEVEL_ICONS := ["🔍", "🐞", "ℹ️", "⚠️", "❌"]

# System mapping with optimized lookups
var _system_map := {
	"seedmanager": "seed_manager",
	"seed": "seed_manager",
	"worldgen": "world_generator",
	"world": "world_generator",
	"entities": "entity_generation",
	"entity": "entity_generation",
	"physics": "physics",
	"ui": "ui",
	"components": "components",
	"component": "components",
	"input": "ui",
	"audio": "audio"
}

# Cached level strings for faster logging
var _level_strings := ["VERBOSE", "DEBUG", "INFO", "WARNING", "ERROR"]

# Call site caching to reduce string operations
var _last_call_sites := {}
var _call_site_counter := 0
const MAX_CALL_SITES := 100

func _init() -> void:
	_auto_id_counter = 0
	if log_to_file:
		_open_log_file()

func _ready() -> void:
	# Find GameSettings in a more robust way
	await get_tree().process_frame
	_find_game_settings()
	
	info("Logger", "Logger initialized with level: %s" % LogLevel.keys()[log_level])
	debug("Logger", "Debug systems available: %s" % _system_map.values().filter(func(x): return _system_map.values().count(x) == 1))

func _find_game_settings() -> void:
	var main_scene = get_tree().current_scene
	_game_settings = main_scene.get_node_or_null("GameSettings")
	
	if _game_settings:
		if not _game_settings.is_connected("debug_settings_changed", _on_debug_settings_changed):
			_game_settings.connect("debug_settings_changed", _on_debug_settings_changed)
		_update_from_settings(_game_settings)
	else:
		push_warning("Logger: GameSettings not found!")

func _open_log_file() -> void:
	_log_file = FileAccess.open(log_file_path, FileAccess.WRITE)
	if _log_file:
		_log_file.store_line("=== Log started at %s ===" % Time.get_datetime_string_from_system())
	else:
		push_error("Failed to open log file: %s" % log_file_path)

func _on_debug_settings_changed(debug_settings: Dictionary) -> void:
	_update_from_settings(_game_settings)

func _update_from_settings(game_settings: Node) -> void:
	enabled = game_settings.debug_mode
	log_level = LogLevel.DEBUG if game_settings.debug_logging else LogLevel.INFO
	
	if enabled:
		info("Logger", "Logging settings updated, level: %s" % LogLevel.keys()[log_level])

# Core logging methods
func verbose(source: String, message: String, data = null) -> void:
	_log(LogLevel.VERBOSE, source, message, data)

func debug(source: String, message: String, data = null) -> void:
	_log(LogLevel.DEBUG, source, message, data)

func info(source: String, message: String, data = null) -> void:
	_log(LogLevel.INFO, source, message, data)

func warning(source: String, message: String, data = null) -> void:
	_log(LogLevel.WARNING, source, message, data)

func error(source: String, message: String, data = null) -> void:
	_log(LogLevel.ERROR, source, message, data)

# Common use case helper methods
func debug_value(source: String, value_name: String, value) -> void:
	debug(source, "%s = %s" % [value_name, value])

func debug_method(source: String, method_name: String, params = null) -> int:
	var call_id = _get_auto_id()
	debug(source, "→ %s(%s) [%d]" % [method_name, params if params != null else "", call_id])
	return call_id

func debug_method_result(source: String, call_id: int, result = null) -> void:
	debug(source, "← [%d] returned %s" % [call_id, result])

func debug_if(source: String, message: String, condition: bool) -> void:
	if condition:
		debug(source, message)

# Component helper methods
func component_state_change(component: Node, property: String, old_value, new_value) -> void:
	debug(component.name, "State changed: %s: %s → %s" % [property, old_value, new_value])

func component_enabled(component: Node) -> void:
	debug(component.name, "Component enabled")

func component_disabled(component: Node) -> void:
	debug(component.name, "Component disabled")

# Main log implementation
func _log(level: int, source: String, message: String, data = null) -> void:
	# Early exit for performance
	if not enabled or level < log_level:
		return
		
	# Special logic for non-warning/error levels
	if level < LogLevel.WARNING and not _is_system_enabled(source):
		return
	
	var time_str := Time.get_time_string_from_system()
	var log_message := "%s %s [%s] %s" % [
		time_str, 
		LEVEL_ICONS[level],
		source, 
		message
	]
	
	# Add extra data if provided
	if data != null:
		match typeof(data):
			TYPE_DICTIONARY, TYPE_ARRAY:
				log_message += "\n    Data: " + JSON.stringify(data)
			TYPE_OBJECT:
				if data.has_method("to_string"):
					log_message += "\n    Data: " + data.to_string()
				else:
					log_message += "\n    Data: [Object]"
			_:
				log_message += "\n    Data: " + str(data)
	
	# Output based on level
	match level:
		LogLevel.WARNING: push_warning(log_message)
		LogLevel.ERROR: push_error(log_message)
		_: print(log_message)
	
	# Write to file if enabled
	if log_to_file and _log_file:
		_log_file.store_line(log_message)

# Get a simplified stack trace (up to 3 levels)
func get_stack_trace() -> String:
	var stack := get_stack()
	if stack.size() <= 2:  # Skip the Logger's own frames
		return ""
		
	var trace := ""
	var start_frame := 2  # Skip this method and _log
	# Fixed type inference by explicitly typing end_frame as int
	var end_frame: int = min(5, stack.size())
	
	for i in range(start_frame, end_frame):
		var frame = stack[i]
		trace += "%s:%d in %s" % [frame.source.get_file(), frame.line, frame.function]
		if i < end_frame - 1:
			trace += " ← "
			
	return trace

# Check if debugging is enabled for a specific system
func _is_system_enabled(system_name: String) -> bool:
	if not _game_settings:
		return false
	
	# Convert system name to lowercase and without spaces for mapping
	var key: String = system_name.to_lower().replace(" ", "")
	
	# Return result without storing the dictionary value in a variable
	if _system_map.has(key):
		return _game_settings.get_debug_status(_system_map[key])
	else:
		return _game_settings.get_debug_status(key)

# Generate a sequential ID for tracking method calls
func _get_auto_id() -> int:
	_auto_id_counter += 1
	return _auto_id_counter

# Close the log file when shutting down
func close() -> void:
	if _log_file:
		_log_file.close()
		_log_file = null

# Save/restore current log state
func get_current_config() -> Dictionary:
	return {
		"enabled": enabled,
		"log_level": log_level,
		"log_to_file": log_to_file
	}

func restore_config(config: Dictionary) -> void:
	if config.has("enabled"):
		enabled = config.enabled
	if config.has("log_level"):
		log_level = config.log_level
	if config.has("log_to_file"):
		log_to_file = config.log_to_file
		if log_to_file and not _log_file:
			_open_log_file()
	
	info("Logger", "Config restored: level=%s, enabled=%s" % [
		LogLevel.keys()[log_level], enabled
	])
