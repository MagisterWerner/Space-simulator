# scripts/debug_logger.gd
# =========================
# Purpose:
#   Provides logging functionality with different log levels
#   Works in conjunction with GameSettings to enable/disable debug logs
extends Node

# Log levels
enum LogLevel {
	ERROR = 0,
	WARNING = 1,
	INFO = 2,
	DEBUG = 3,
	TRACE = 4
}

# Colorize console output
const COLOR_ERROR = "ff5555"
const COLOR_WARNING = "ffff55"
const COLOR_INFO = "55ffff"
const COLOR_DEBUG = "aaaaaa"
const COLOR_TRACE = "555555"

# Configuration
@export var enabled: bool = true
@export var log_level: LogLevel = LogLevel.INFO
@export var include_stack_trace: bool = true
@export var include_timestamp: bool = true
@export var log_to_file: bool = false
@export var log_file_path: String = "user://debug_log.txt"

# Internals
var _initialized: bool = false
var _file: FileAccess = null
var _log_file_enabled: bool = false
var _log_buffer: Array = []
var _buffer_max_size: int = 1000
var _systems_enabled: Dictionary = {}

func _ready() -> void:
	# Initialize logging
	_initialized = true
	
	# Check if GameSettings exists
	if not Engine.has_singleton("GameSettings"):
		push_warning("DebugLogger: GameSettings singleton not found. Logging configuration not applied.")
		return
	
	# Connect to GameSettings for debug configuration changes
	var settings = get_node("/root/GameSettings")
	if settings:
		settings.connect("debug_settings_changed", _on_debug_settings_changed)
		_update_from_settings(settings)
		
		# Log initialization
		info("DebugLogger", "Debug logger initialized.")
	else:
		push_warning("DebugLogger: Failed to get GameSettings node. Logging configuration not applied.")
	
	# Initialize log file if configured
	if log_to_file:
		_open_log_file()

# Connect to GameSettings
func _update_from_settings(settings) -> void:
	# Update from GameSettings
	enabled = settings.debug_mode and settings.debug_logging
	
	# Get enabled systems
	_systems_enabled = {
		"master": settings.debug_mode,
		"logging": settings.debug_logging,
		"grid": settings.debug_grid,
		"seed_manager": settings.debug_seed_manager,
		"world_generator": settings.debug_world_generator,
		"entity_generation": settings.debug_entity_generation,
		"physics": settings.debug_physics,
		"ui": settings.debug_ui,
		"components": settings.debug_components
	}
	
	# Debug message
	if enabled:
		trace("DebugLogger", "Debug logging enabled. Log level: %s" % _get_level_name(log_level))

# Handle debug settings changed
func _on_debug_settings_changed(debug_settings: Dictionary) -> void:
	enabled = debug_settings.master and debug_settings.logging
	_systems_enabled = debug_settings
	
	if enabled:
		trace("DebugLogger", "Debug settings updated.")

# PUBLIC METHODS

# Check if logging is enabled for a system
func is_system_logging_enabled(system_name: String) -> bool:
	if not enabled:
		return false
		
	# Special case - "logging" system is always enabled if debug_mode is on
	if system_name == "logging":
		return _systems_enabled.master
		
	# Check if system exists and is enabled
	if _systems_enabled.has(system_name):
		return _systems_enabled.master and _systems_enabled[system_name]
	
	# Unknown system (default is disabled)
	return false

# Log error message with optional context data
func error(system: String, message: String, context = null) -> void:
	_log(LogLevel.ERROR, system, message, context)

# Log warning message with optional context data
func warning(system: String, message: String, context = null) -> void:
	_log(LogLevel.WARNING, system, message, context)

# Log info message with optional context data
func info(system: String, message: String, context = null) -> void:
	_log(LogLevel.INFO, system, message, context)

# Log debug message with optional context data
func debug(system: String, message: String, context = null) -> void:
	_log(LogLevel.DEBUG, system, message, context)

# Log trace message with optional context data
func trace(system: String, message: String, context = null) -> void:
	_log(LogLevel.TRACE, system, message, context)

# PRIVATE METHODS

# Core logging function
func _log(level: LogLevel, system: String, message: String, context = null) -> void:
	if not _initialized or not enabled or level > log_level:
		return
		
	# Check if the system has logging enabled
	if not is_system_logging_enabled(system):
		return
	
	# Format timestamp
	var timestamp = ""
	if include_timestamp:
		var datetime = Time.get_datetime_dict_from_system()
		timestamp = "[%02d:%02d:%02d] " % [datetime.hour, datetime.minute, datetime.second]
	
	# Choose color based on level
	var color = _get_level_color(level)
	
	# Format log entry
	var log_entry = "%s[%s] [%s] %s" % [timestamp, _get_level_name(level), system, message]
	
	# Print to console with color
	print_rich("[color=%s]%s[/color]" % [color, log_entry])
	
	# Add context data if provided
	if context != null:
		print_rich("[color=%s]  Context: %s[/color]" % [color, str(context)])
	
	# Print stack trace if needed
	if include_stack_trace and level <= LogLevel.ERROR:
		print_rich("[color=%s]  Stack Trace: %s[/color]" % [color, get_stack()])
	
	# Add to buffer
	_add_to_buffer(log_entry)
	
	# Write to file if enabled
	if _log_file_enabled:
		_write_to_file(log_entry)
		if context != null:
			_write_to_file("  Context: " + str(context))

# Add log entry to internal buffer
func _add_to_buffer(entry: String) -> void:
	_log_buffer.append(entry)
	
	# Trim buffer if it gets too large
	if _log_buffer.size() > _buffer_max_size:
		_log_buffer.pop_front()

# Open log file
func _open_log_file() -> void:
	if not log_to_file:
		return
		
	# Create or open the log file
	_file = FileAccess.open(log_file_path, FileAccess.WRITE)
	
	if _file:
		_log_file_enabled = true
		
		# Add header
		var datetime = Time.get_datetime_dict_from_system()
		var date_str = "%04d-%02d-%02d %02d:%02d:%02d" % [
			datetime.year, datetime.month, datetime.day,
			datetime.hour, datetime.minute, datetime.second
		]
		
		_file.store_line("=== DEBUG LOG STARTED: " + date_str + " ===")
	else:
		push_error("DebugLogger: Failed to open log file at: " + log_file_path)
		_log_file_enabled = false

# Write entry to log file
func _write_to_file(entry: String) -> void:
	if _file and _log_file_enabled:
		_file.store_line(entry)

# Close log file
func _close_log_file() -> void:
	if _file:
		# Add footer
		var datetime = Time.get_datetime_dict_from_system()
		var date_str = "%04d-%02d-%02d %02d:%02d:%02d" % [
			datetime.year, datetime.month, datetime.day,
			datetime.hour, datetime.minute, datetime.second
		]
		
		_file.store_line("=== DEBUG LOG ENDED: " + date_str + " ===")
		_file.close()
		_file = null
		_log_file_enabled = false

# Get the string name of a log level
func _get_level_name(level: LogLevel) -> String:
	match level:
		LogLevel.ERROR:
			return "ERROR"
		LogLevel.WARNING:
			return "WARNING"
		LogLevel.INFO:
			return "INFO"
		LogLevel.DEBUG:
			return "DEBUG"
		LogLevel.TRACE:
			return "TRACE"
		_:
			return "UNKNOWN"

# Get the color for a log level
func _get_level_color(level: LogLevel) -> String:
	match level:
		LogLevel.ERROR:
			return COLOR_ERROR
		LogLevel.WARNING:
			return COLOR_WARNING
		LogLevel.INFO:
			return COLOR_INFO
		LogLevel.DEBUG:
			return COLOR_DEBUG
		LogLevel.TRACE:
			return COLOR_TRACE
		_:
			return COLOR_INFO

# Cleanup on exit
func _exit_tree() -> void:
	_close_log_file()
