# scripts/utils/debug_logger.gd
# A robust logging utility for Godot projects that respects debug toggles
extends Node

# Global settings 
var enabled: bool = OS.is_debug_build()
var log_level: int = LogLevel.INFO
var log_to_file: bool = false
var log_file_path: String = "user://debug_log.txt"
var _log_file = null
var _game_settings = null

enum LogLevel {
	VERBOSE = 0,  # Detailed logging
	DEBUG = 1,    # Debug info
	INFO = 2,     # Normal info
	WARNING = 3,  # Warnings
	ERROR = 4,    # Errors
	NONE = 5      # No logging
}

# System to debug toggle mapping
var _system_map = {
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
	"input": "ui"
}

func _init():
	if log_to_file:
		_open_log_file()

func _ready():
	# Find GameSettings
	var main_scene = get_tree().current_scene
	_game_settings = main_scene.get_node_or_null("GameSettings")
	
	if _game_settings:
		# Connect to debug settings changes
		if not _game_settings.is_connected("debug_settings_changed", _on_debug_settings_changed):
			_game_settings.connect("debug_settings_changed", _on_debug_settings_changed)
		
		# Initialize based on current settings
		_update_from_settings(_game_settings)
	
	print("DebugLogger initialized, log level: " + str(LogLevel.keys()[log_level]))

func _open_log_file():
	_log_file = FileAccess.open(log_file_path, FileAccess.WRITE)
	if _log_file:
		_log_file.store_line("=== Log started at " + Time.get_datetime_string_from_system() + " ===")
	else:
		push_error("Failed to open log file: " + log_file_path)

func _on_debug_settings_changed(debug_settings: Dictionary) -> void:
	_update_from_settings(_game_settings)

func _update_from_settings(game_settings) -> void:
	# Master debug must be on
	enabled = game_settings.debug_mode
	
	# Logging setting affects log level
	if game_settings.debug_logging:
		log_level = LogLevel.DEBUG
	else:
		log_level = LogLevel.INFO
		
	# Log update if we're enabled
	if enabled:
		info("Logger", "Logging settings updated, level: " + LogLevel.keys()[log_level])

func verbose(source: String, message: String, append_stack: bool = false):
	_log(LogLevel.VERBOSE, source, message, append_stack)

func debug(source: String, message: String, append_stack: bool = false):
	_log(LogLevel.DEBUG, source, message, append_stack)

func info(source: String, message: String, append_stack: bool = false):
	_log(LogLevel.INFO, source, message, append_stack)

func warning(source: String, message: String, append_stack: bool = false):
	_log(LogLevel.WARNING, source, message, append_stack)

func error(source: String, message: String, append_stack: bool = true):
	_log(LogLevel.ERROR, source, message, append_stack)

func _log(level: int, source: String, message: String, append_stack: bool):
	# Skip if globally disabled or level too low
	if not enabled or level < log_level:
		return
		
	# Special case for errors and warnings - always log these
	if level < LogLevel.WARNING:
		# Check if the system is debug-enabled
		if not _is_system_enabled(source):
			return
	
	var level_str = ""
	match level:
		LogLevel.VERBOSE: level_str = "VERBOSE"
		LogLevel.DEBUG: level_str = "DEBUG"
		LogLevel.INFO: level_str = "INFO"
		LogLevel.WARNING: level_str = "WARNING"
		LogLevel.ERROR: level_str = "ERROR"
	
	var time_str = Time.get_time_string_from_system()
	var log_message = "[%s][%s][%s] %s" % [time_str, level_str, source, message]
	
	if append_stack:
		log_message += "\n    Stack: " + get_stack_trace()
	
	# Print to console
	match level:
		LogLevel.WARNING: push_warning(log_message)
		LogLevel.ERROR: push_error(log_message)
		_: print(log_message)
	
	# Save to file if enabled
	if log_to_file and _log_file:
		_log_file.store_line(log_message)

# Get simplified stack trace from the built-in get_stack() function
func get_stack_trace() -> String:
	var stack = get_stack()
	var stack_str = ""
	
	# Limit to 3 levels for readability
	for i in range(min(3, stack.size())):
		if i >= stack.size():
			break
			
		var frame = stack[i]
		stack_str += frame.source + ":" + str(frame.line) + " in " + frame.function
		if i < min(3, stack.size()) - 1:
			stack_str += " ← "
			
	return stack_str

# Check if a system's debug is enabled
func _is_system_enabled(system_name: String) -> bool:
	if not _game_settings:
		return false
	
	# Normalize system name
	var system_key = system_name.to_lower()
	system_key = system_key.replace(" ", "")
	
	# Map to correct debug option if needed
	if _system_map.has(system_key):
		system_key = _system_map[system_key]
	
	# Check the setting
	return _game_settings.get_debug_status(system_key)

# Call this when quitting the game
func close():
	if _log_file:
		_log_file.close()
