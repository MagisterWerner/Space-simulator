extends Node

enum LogLevel {
	VERBOSE = 0,
	DEBUG = 1,
	INFO = 2,
	WARNING = 3,
	ERROR = 4,
	NONE = 5
}

var enabled := OS.is_debug_build()
var log_level := LogLevel.INFO
var log_to_file := false
var log_file_path := "user://debug_log.txt"
var _log_file = null
var _game_settings = null

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
	"input": "ui"
}

# Cached level strings for faster logging
var _level_strings := ["VERBOSE", "DEBUG", "INFO", "WARNING", "ERROR"]

func _init() -> void:
	if log_to_file:
		_open_log_file()

func _ready() -> void:
	var main_scene = get_tree().current_scene
	_game_settings = main_scene.get_node_or_null("GameSettings")
	
	if _game_settings:
		if not _game_settings.is_connected("debug_settings_changed", _on_debug_settings_changed):
			_game_settings.connect("debug_settings_changed", _on_debug_settings_changed)
		_update_from_settings(_game_settings)
	
	print("DebugLogger initialized, level: %s" % LogLevel.keys()[log_level])

func _open_log_file() -> void:
	_log_file = FileAccess.open(log_file_path, FileAccess.WRITE)
	if _log_file:
		_log_file.store_line("=== Log started at %s ===" % Time.get_datetime_string_from_system())
	else:
		push_error("Failed to open log file: %s" % log_file_path)

func _on_debug_settings_changed(_debug_settings: Dictionary) -> void:
	_update_from_settings(_game_settings)

func _update_from_settings(game_settings: Node) -> void:
	enabled = game_settings.debug_mode
	log_level = LogLevel.DEBUG if game_settings.debug_logging else LogLevel.INFO
	
	if enabled:
		info("Logger", "Logging settings updated, level: %s" % LogLevel.keys()[log_level])

func verbose(source: String, message: String, append_stack: bool = false) -> void:
	_log(LogLevel.VERBOSE, source, message, append_stack)

func debug(source: String, message: String, append_stack: bool = false) -> void:
	_log(LogLevel.DEBUG, source, message, append_stack)

func info(source: String, message: String, append_stack: bool = false) -> void:
	_log(LogLevel.INFO, source, message, append_stack)

func warning(source: String, message: String, append_stack: bool = false) -> void:
	_log(LogLevel.WARNING, source, message, append_stack)

func error(source: String, message: String, append_stack: bool = true) -> void:
	_log(LogLevel.ERROR, source, message, append_stack)

func _log(level: int, source: String, message: String, append_stack: bool) -> void:
	# Early exit for performance
	if not enabled or level < log_level:
		return
		
	# Special logic for non-warning/error levels
	if level < LogLevel.WARNING and not _is_system_enabled(source):
		return
	
	var time_str := Time.get_time_string_from_system()
	var log_message := "[%s][%s][%s] %s" % [time_str, _level_strings[level], source, message]
	
	if append_stack:
		log_message += "\n    Stack: " + get_stack_trace()
	
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
	if stack.size() == 0:
		return ""
		
	var trace := ""
	var levels: int = min(3, stack.size())
	
	for i in range(levels):
		var frame = stack[i]
		trace += "%s:%d in %s" % [frame.source, frame.line, frame.function]
		if i < levels - 1:
			trace += " ← "
			
	return trace

# Check if debugging is enabled for a specific system
func _is_system_enabled(system_name: String) -> bool:
	if not _game_settings:
		return false
	
	# Convert system name to lowercase and without spaces for mapping
	var key: String = system_name.to_lower().replace(" ", "")
	
	# Use a different approach to avoid type inference issues
	var mapped_key: String
	if _system_map.has(key):
		mapped_key = String(_system_map[key])
	else:
		mapped_key = key
	
	return _game_settings.get_debug_status(mapped_key)

# Close the log file when shutting down
func close() -> void:
	if _log_file:
		_log_file.close()
		_log_file = null
