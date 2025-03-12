extends Node
class_name AsyncGeneratorComponent

# Signals
signal generation_completed(result)
signal generation_failed(error)
signal generation_started(request_id)

# Request tracking
var current_request_id = null
var auto_cancel = true
var last_result = null
var last_error = null
var request_in_progress = false

# Initialization
func _ready():
	# Connect to the GenerationManager signals
	if has_node("/root/GenerationManager"):
		GenerationManager.generation_completed.connect(_on_generation_completed)
		GenerationManager.generation_failed.connect(_on_generation_failed)

# Cleanup
func _exit_tree():
	# Auto-cancel pending request when node is removed
	if auto_cancel and current_request_id and request_in_progress:
		cancel_request()
		
	# Disconnect from signals
	if has_node("/root/GenerationManager"):
		if GenerationManager.generation_completed.is_connected(_on_generation_completed):
			GenerationManager.generation_completed.disconnect(_on_generation_completed)
		if GenerationManager.generation_failed.is_connected(_on_generation_failed):
			GenerationManager.generation_failed.disconnect(_on_generation_failed)

# Request a planet texture
func request_planet(seed_value, is_gaseous = false, theme_override = -1, priority = GenerationManager.Priority.NORMAL):
	# Cancel any pending request
	if auto_cancel and current_request_id and request_in_progress:
		cancel_request()
	
	# Create new request
	current_request_id = GenerationManager.request_planet(seed_value, is_gaseous, theme_override, priority)
	request_in_progress = true
	
	# Emit signal with the request ID
	generation_started.emit(current_request_id)
	
	return current_request_id

# Request a moon texture
func request_moon(seed_value, moon_type = MoonGenerator.MoonType.ROCKY, is_gaseous = false, priority = GenerationManager.Priority.NORMAL):
	# Cancel any pending request
	if auto_cancel and current_request_id and request_in_progress:
		cancel_request()
	
	# Create new request
	current_request_id = GenerationManager.request_moon(seed_value, moon_type, is_gaseous, priority)
	request_in_progress = true
	
	# Emit signal with the request ID
	generation_started.emit(current_request_id)
	
	return current_request_id

# Request an asteroid texture
func request_asteroid(seed_value, size = 32, priority = GenerationManager.Priority.NORMAL):
	# Cancel any pending request
	if auto_cancel and current_request_id and request_in_progress:
		cancel_request()
	
	# Create new request
	current_request_id = GenerationManager.request_asteroid(seed_value, size, priority)
	request_in_progress = true
	
	# Emit signal with the request ID
	generation_started.emit(current_request_id)
	
	return current_request_id

# Request an atmosphere texture
func request_atmosphere(theme, seed_value, planet_size = 0, priority = GenerationManager.Priority.NORMAL):
	# Cancel any pending request
	if auto_cancel and current_request_id and request_in_progress:
		cancel_request()
	
	# Create new request
	current_request_id = GenerationManager.request_atmosphere(theme, seed_value, planet_size, priority)
	request_in_progress = true
	
	# Emit signal with the request ID
	generation_started.emit(current_request_id)
	
	return current_request_id

# Cancel the current request
func cancel_request():
	if current_request_id and request_in_progress:
		var was_canceled = GenerationManager.cancel_request(current_request_id)
		if was_canceled:
			request_in_progress = false
			return true
	return false

# Check if a request is in progress
func is_generating():
	return request_in_progress

# Handle generation completion
func _on_generation_completed(request_id, result):
	# Check if this is our request
	if request_id != current_request_id:
		return
	
	request_in_progress = false
	last_result = result
	generation_completed.emit(result)

# Handle generation failure
func _on_generation_failed(request_id, error):
	# Check if this is our request
	if request_id != current_request_id:
		return
	
	request_in_progress = false
	last_error = error
	generation_failed.emit(error)
