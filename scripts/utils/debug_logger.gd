# scripts/utils/debug_logger.gd
extends Node
class_name DebugLogger

# Global settings 
var enabled: bool = OS.is_debug_build()
var log_level: int = LogLevel.INFO
var log_to_file: bool = false
var log_file_path: String = "user://debug_log.txt"
var _log_file = null

enum LogLevel {
	VERBOSE = 0,  # Detailed logging
	DEBUG = 1,    # Debug info
	INFO = 2,     # Normal info
	WARNING = 3,  # Warnings
	ERROR = 4,    # Errors
	NONE = 5      # No logging
}

func _init():
	if log_to_file:
		_open_log_file()

func _open_log_file():
	_log_file = FileAccess.open(log_file_path, FileAccess.WRITE)
	if _log_file:
		_log_file.store_line("=== Log started at " + Time.get_datetime_string_from_system() + " ===")
	else:
		push_error("Failed to open log file: " + log_file_path)

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
	if not enabled or level < log_level:
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
		log_message += "\n    Stack: " + get_stack()
	
	# Print to console
	match level:
		LogLevel.WARNING: push_warning(log_message)
		LogLevel.ERROR: push_error(log_message)
		_: print(log_message)
	
	# Save to file if enabled
	if log_to_file and _log_file:
		_log_file.store_line(log_message)

# Get simplified stack trace
func get_stack() -> String:
	var stack = get_stack()
	var stack_str = ""
	for i in range(min(3, stack.size())): # Show only 3 levels
		var frame = stack[i]
		stack_str += frame.source + ":" + str(frame.line) + " in " + frame.function
		if i < stack.size() - 1:
			stack_str += " ← "
	return stack_str

# Call this when quitting the game
func close():
	if _log_file:
		_log_file.close()

# Example usage:
# Replace:
# debug_print("Player took damage")
# With:
# DebugLogger.info("PlayerShip", "Player took damage")
