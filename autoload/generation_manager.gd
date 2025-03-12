extends Node
# GenerationManager - Asynchronous texture generation system
# Manages threaded generation of game assets to prevent stuttering

# Import required generator classes
const AsteroidGenerator = preload("res://scripts/generators/asteroid_generator.gd")

signal generation_completed(request_id, result)
signal generation_progress(request_id, progress) 
signal generation_failed(request_id, error)
signal queue_size_changed(pending_count)

# Generation types
enum GenerationType {
	PLANET,
	MOON,
	ASTEROID,
	ATMOSPHERE
}

# Priority levels
enum Priority {
	LOW = 0,
	NORMAL = 1,
	HIGH = 2,
	CRITICAL = 3
}

# Request status
enum RequestStatus {
	PENDING,
	PROCESSING,
	COMPLETED,
	FAILED,
	CANCELED
}

# Queue and tracking
var generation_queue = []
var active_requests = {}
var results_cache = {}
var cache_access_time = {}

# Threading
var _thread = null
var _thread_active = false
var _mutex = Mutex.new()
var _semaphore = Semaphore.new()

# Configuration
var max_cache_size = 100
var enable_cache = true
var debug_mode = false
var _initialized = false
var _last_request_id = 0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_initialize")

func _initialize():
	if _initialized:
		return
	
	# Check for debug settings
	if has_node("/root/GameSettings"):
		var game_settings = get_node("/root/GameSettings")
		debug_mode = game_settings.debug_mode
	
	# Start the worker thread
	_thread = Thread.new()
	_thread_active = true
	var err = _thread.start(_process_queue)
	if err != OK:
		push_error("GenerationManager: Failed to start thread. Error code: " + str(err))
		return
	
	_initialized = true
	
	if debug_mode:
		print("GenerationManager initialized")

# Clean up when the scene exits
func _exit_tree():
	if _thread_active:
		_thread_active = false
		_semaphore.post()  # Wake up the thread so it can exit
		_thread.wait_to_finish()

# Process generation requests in the background
func _process_queue():
	while _thread_active:
		# Wait for a request to process
		_semaphore.wait()
		
		if not _thread_active:
			break
		
		var request = null
		
		# Get the highest priority request
		_mutex.lock()
		if not generation_queue.is_empty():
			# Sort by priority (highest first)
			generation_queue.sort_custom(Callable(self, "_sort_by_priority"))
			request = generation_queue.pop_front()
			request.status = RequestStatus.PROCESSING
			active_requests[request.id] = request
			
			# Notify queue size change
			call_deferred("emit_signal", "queue_size_changed", generation_queue.size())
		_mutex.unlock()
		
		if request:
			var result = null
			var error = null
			
			# Process the request
			match request.type:
				GenerationType.PLANET:
					result = _generate_planet(request)
				GenerationType.MOON:
					result = _generate_moon(request)
				GenerationType.ASTEROID:
					result = _generate_asteroid(request)
				GenerationType.ATMOSPHERE:
					result = _generate_atmosphere(request)
				_:
					error = "Unknown generation type"
			
			# Handle the result
			_mutex.lock()
			if error:
				request.status = RequestStatus.FAILED
				request.error = error
				call_deferred("emit_signal", "generation_failed", request.id, error)
			else:
				request.status = RequestStatus.COMPLETED
				request.result = result
				
				# Cache the result if enabled
				if enable_cache and not request.skip_cache:
					_add_to_cache(request.cache_key, result)
				
				call_deferred("emit_signal", "generation_completed", request.id, result)
			
			active_requests.erase(request.id)
			_mutex.unlock()

# Sort function for priority queue
func _sort_by_priority(a, b):
	if a.priority == b.priority:
		return a.timestamp < b.timestamp  # FIFO for same priority
	return a.priority > b.priority  # Higher priority first

# Generate a planet
func _generate_planet(request):
	var is_gaseous = request.params.get("is_gaseous", false)
	var theme_override = request.params.get("theme_override", -1)
	var seed_value = request.params.get("seed_value", 0)
	
	# Use existing generators
	if is_gaseous:
		return PlanetGeneratorGaseous.get_gaseous_texture(seed_value, theme_override)
	else:
		return PlanetGeneratorTerran.get_terran_texture(seed_value, theme_override)

# Generate a moon
func _generate_moon(request):
	var seed_value = request.params.get("seed_value", 0)
	var moon_type = request.params.get("moon_type", MoonGenerator.MoonType.ROCKY)
	var is_gaseous = request.params.get("is_gaseous", false)
	
	return MoonGenerator.get_moon_texture(seed_value, moon_type, is_gaseous)

# Generate an asteroid
func _generate_asteroid(request):
	var seed_value = request.params.get("seed_value", 0)
	var size = request.params.get("size", 32)
	
	var generator = AsteroidGenerator.new()
	generator.main_rng = RandomNumberGenerator.new()
	generator.main_rng.seed = seed_value
	generator.seed_value = seed_value
	
	# Configure generator parameters based on size
	if size == AsteroidGenerator.ASTEROID_SIZE_SMALL:
		generator.CRATER_COUNT_MIN = 1
		generator.CRATER_COUNT_MAX = 2
		generator.CRATER_PIXEL_SIZE_MIN = 3
		generator.CRATER_PIXEL_SIZE_MAX = 4
	elif size == AsteroidGenerator.ASTEROID_SIZE_LARGE:
		generator.CRATER_COUNT_MIN = 3
		generator.CRATER_COUNT_MAX = 5
		generator.CRATER_PIXEL_SIZE_MIN = 4
		generator.CRATER_PIXEL_SIZE_MAX = 6
	
	generator.set_random_shape_params()
	var texture = generator.create_asteroid_texture()
	
	return texture

# Generate an atmosphere
func _generate_atmosphere(request):
	var theme = request.params.get("theme", 0)
	var seed_value = request.params.get("seed_value", 0)
	var planet_size = request.params.get("planet_size", 0)
	
	var atmosphere_data = AtmosphereGenerator.new().generate_atmosphere_data(theme, seed_value)
	return AtmosphereGenerator.get_atmosphere_texture(
		theme, 
		seed_value, 
		atmosphere_data.color, 
		atmosphere_data.thickness, 
		planet_size
	)

# Add a result to the cache
func _add_to_cache(cache_key, result):
	_clean_cache_if_needed()
	
	results_cache[cache_key] = result
	cache_access_time[cache_key] = Time.get_ticks_msec()

# Clean the cache if it's too large
func _clean_cache_if_needed():
	if results_cache.size() < max_cache_size:
		return
	
	# Remove oldest entries
	var entries = []
	for key in cache_access_time:
		entries.append({"key": key, "time": cache_access_time[key]})
	
	entries.sort_custom(Callable(self, "_sort_by_access_time"))
	
	# Remove oldest entries to get below max_cache_size
	var to_remove = entries.size() - max_cache_size + 10  # Remove a few extra to avoid frequent cleaning
	for i in range(to_remove):
		if i < entries.size():
			var key = entries[i].key
			results_cache.erase(key)
			cache_access_time.erase(key)

# Sort function for cache cleaning
func _sort_by_access_time(a, b):
	return a.time < b.time  # Oldest first

# Create a unique cache key
func _create_cache_key(type, params):
	var key_parts = [str(type)]
	
	match type:
		GenerationType.PLANET:
			key_parts.append(str(params.get("seed_value", 0)))
			key_parts.append(str(params.get("is_gaseous", false)))
			key_parts.append(str(params.get("theme_override", -1)))
		
		GenerationType.MOON:
			key_parts.append(str(params.get("seed_value", 0)))
			key_parts.append(str(params.get("moon_type", 0)))
			key_parts.append(str(params.get("is_gaseous", false)))
		
		GenerationType.ASTEROID:
			key_parts.append(str(params.get("seed_value", 0)))
			key_parts.append(str(params.get("size", 32)))
		
		GenerationType.ATMOSPHERE:
			key_parts.append(str(params.get("theme", 0)))
			key_parts.append(str(params.get("seed_value", 0)))
			key_parts.append(str(params.get("planet_size", 0)))
	
	return key_parts.join("_")

# Generate a unique request ID
func _generate_request_id():
	_last_request_id += 1
	return str(_last_request_id)

# Create a generation request
func create_request(type, params, priority = Priority.NORMAL, skip_cache = false):
	var cache_key = _create_cache_key(type, params)
	
	# Check cache first
	if enable_cache and not skip_cache and results_cache.has(cache_key):
		cache_access_time[cache_key] = Time.get_ticks_msec()
		
		# Create a request object with the cached result
		var request_id = _generate_request_id()
		var request = {
			"id": request_id,
			"type": type,
			"params": params,
			"priority": priority,
			"timestamp": Time.get_ticks_msec(),
			"status": RequestStatus.COMPLETED,
			"result": results_cache[cache_key],
			"cache_key": cache_key,
			"skip_cache": skip_cache
		}
		
		# Return immediately with the cached result
		call_deferred("emit_signal", "generation_completed", request_id, request.result)
		return request_id
	
	# Create a new request
	var request_id = _generate_request_id()
	var request = {
		"id": request_id,
		"type": type,
		"params": params,
		"priority": priority,
		"timestamp": Time.get_ticks_msec(),
		"status": RequestStatus.PENDING,
		"result": null,
		"error": null,
		"cache_key": cache_key,
		"skip_cache": skip_cache
	}
	
	# Add to queue
	_mutex.lock()
	generation_queue.append(request)
	call_deferred("emit_signal", "queue_size_changed", generation_queue.size())
	_mutex.unlock()
	
	# Signal the thread to wake up
	_semaphore.post()
	
	return request_id

# Check the status of a request
func get_request_status(request_id):
	_mutex.lock()
	var status = null
	
	if active_requests.has(request_id):
		status = active_requests[request_id].status
	else:
		for request in generation_queue:
			if request.id == request_id:
				status = request.status
				break
	
	_mutex.unlock()
	return status

# Cancel a pending request
func cancel_request(request_id):
	_mutex.lock()
	
	var index_to_remove = -1
	for i in range(generation_queue.size()):
		if generation_queue[i].id == request_id:
			index_to_remove = i
			break
	
	if index_to_remove >= 0:
		generation_queue.remove_at(index_to_remove)
		call_deferred("emit_signal", "queue_size_changed", generation_queue.size())
		call_deferred("emit_signal", "generation_failed", request_id, "Request canceled")
	
	_mutex.unlock()
	return index_to_remove >= 0

# Clear all pending requests
func clear_queue():
	_mutex.lock()
	generation_queue.clear()
	call_deferred("emit_signal", "queue_size_changed", 0)
	_mutex.unlock()

# Get the number of pending requests
func get_pending_count():
	_mutex.lock()
	var count = generation_queue.size()
	_mutex.unlock()
	return count

# Get the number of active requests
func get_active_count():
	_mutex.lock()
	var count = active_requests.size()
	_mutex.unlock()
	return count

# Convenience methods for different generation types

# Request a planet texture
func request_planet(seed_value, is_gaseous = false, theme_override = -1, priority = Priority.NORMAL):
	var params = {
		"seed_value": seed_value,
		"is_gaseous": is_gaseous,
		"theme_override": theme_override
	}
	return create_request(GenerationType.PLANET, params, priority)

# Request a moon texture
func request_moon(seed_value, moon_type = MoonGenerator.MoonType.ROCKY, is_gaseous = false, priority = Priority.NORMAL):
	var params = {
		"seed_value": seed_value,
		"moon_type": moon_type,
		"is_gaseous": is_gaseous
	}
	return create_request(GenerationType.MOON, params, priority)

# Request an asteroid texture
func request_asteroid(seed_value, size = 32, priority = Priority.NORMAL):
	var params = {
		"seed_value": seed_value,
		"size": size
	}
	return create_request(GenerationType.ASTEROID, params, priority)

# Request an atmosphere texture
func request_atmosphere(theme, seed_value, planet_size = 0, priority = Priority.NORMAL):
	var params = {
		"theme": theme,
		"seed_value": seed_value,
		"planet_size": planet_size
	}
	return create_request(GenerationType.ATMOSPHERE, params, priority)

# Debug features
func print_queue_status():
	if not debug_mode:
		return
	
	_mutex.lock()
	print("Generation Queue: ", generation_queue.size(), " pending, ", active_requests.size(), " active")
	print("Cache Size: ", results_cache.size(), "/", max_cache_size)
	_mutex.unlock()

# Clear the texture cache
func clear_cache():
	_mutex.lock()
	results_cache.clear()
	cache_access_time.clear()
	_mutex.unlock()
	
	# Also clear static caches in generators
	PlanetGeneratorBase.clean_texture_cache()
