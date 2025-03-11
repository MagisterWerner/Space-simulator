# autoload/seed_manager.gd
# Provides deterministic randomization methods using the game seed.
# Core component for procedural generation throughout the game.

extends "res://autoload/base_service.gd"

signal seed_initialized
signal seed_changed(new_seed)
signal debug_mode_changed(enabled)

# Cache for deterministic values
var _noise_generators = {}
var _value_cache = {}
var _max_cache_size = 1000  # Limit the cache size

# Reference to GameSettings
var game_settings: Object = null

# Flags
var debug_mode: bool = false
var enable_cache: bool = true  # Can be toggled for memory optimization
var _seed_initialized: bool = false # Renamed to avoid conflict with base_service.is_initialized

# Default seed to use if GameSettings is not available
const DEFAULT_SEED = 0
var _current_seed: int = DEFAULT_SEED

# Statistics for debugging and profiling
var _stats = {
	"cache_hits": 0,
	"cache_misses": 0,
	"total_requests": 0,
	"last_cache_clear": 0  # Time of last cache clear
}

func _ready() -> void:
	# Wait one frame before registering to ensure ServiceLocator is ready
	await get_tree().process_frame
	register_self()
	
	# Set process mode to continue during pause
	process_mode = Node.PROCESS_MODE_ALWAYS

# Return dependencies required by this service
func get_dependencies() -> Array:
	return [] # SeedManager has no required dependencies

# Initialize this service
func initialize_service() -> void:
	# SeedManager is ready for usage after auto-registration
	_seed_initialized = true
	
	# Find GameSettings if available (optional dependency)
	if has_dependency("GameSettings"):
		game_settings = get_dependency("GameSettings")
		
		# Connect to GameSettings signals
		connect_to_dependency("GameSettings", "seed_changed", _on_game_settings_seed_changed)
		connect_to_dependency("GameSettings", "debug_settings_changed", _on_debug_settings_changed)
		
		# Get initial values from settings
		if game_settings.has_method("get_seed"):
			_current_seed = game_settings.get_seed()
		
		# Check for debug mode properties safely
		if "debug_mode" in game_settings:
			if "debug_seed_manager" in game_settings:
				debug_mode = game_settings.debug_mode and game_settings.debug_seed_manager
			else:
				debug_mode = game_settings.debug_mode
		
		if debug_mode:
			print("SeedManager: Connected to GameSettings, using seed:", _current_seed)
	else:
		print("SeedManager: GameSettings not found, using default seed")
	
	# Mark as initialized and emit signal
	_service_initialized = true
	seed_initialized.emit()
	
	# Record startup time for stats
	_stats.last_cache_clear = Time.get_ticks_msec()

# Public getter for initialization status
func is_seed_ready() -> bool:
	return _seed_initialized

# Handle debug setting changes
func _on_debug_settings_changed(debug_settings: Dictionary) -> void:
	# Update debug mode based on both master toggle and specific toggle
	debug_mode = debug_settings.get("master", false) and debug_settings.get("seed_manager", false)
	debug_mode_changed.emit(debug_mode)
	
	if debug_mode:
		print("SeedManager: Debug mode enabled")
		print_cache_stats()

# Called when GameSettings seed changes
func _on_game_settings_seed_changed(new_seed: int) -> void:
	# Clear caches when seed changes
	_clear_caches()
	_current_seed = new_seed
	
	# Emit our own signal so other systems can update
	seed_changed.emit(new_seed)
	
	if debug_mode:
		print("SeedManager: Seed changed from GameSettings to ", new_seed)

# Get the current seed from internal storage
func get_seed() -> int:
	return _current_seed

# Set the seed directly (used by external systems)
func set_seed(new_seed: int) -> void:
	# Check for early calls during initialization
	if not is_inside_tree():
		# Defer until we're ready
		call_deferred("set_seed", new_seed)
		return
		
	if _current_seed == new_seed:
		return  # No change needed
		
	_current_seed = new_seed
	_clear_caches()
	
	# Emit change signal
	seed_changed.emit(new_seed)
	
	if debug_mode:
		print("SeedManager: Set seed to ", new_seed)

# Get the hash representation of the current seed
func get_seed_hash() -> String:
	if game_settings and game_settings.has_method("get_seed_hash"):
		return game_settings.get_seed_hash()
	return _generate_seed_hash(_current_seed)

# Toggle debug mode
func set_debug_mode(enable: bool) -> void:
	debug_mode = enable
	debug_mode_changed.emit(debug_mode)
	
	if debug_mode:
		# Print cache statistics when enabling debug mode
		print_cache_stats()

# Print cache statistics - useful for debugging and optimization
func print_cache_stats() -> void:
	debug_print("Cache Statistics:")
	debug_print("- Cache size: " + str(_value_cache.size()) + "/" + str(_max_cache_size))
	debug_print("- Total requests: " + str(_stats.total_requests))
	
	var hit_percent = 0
	if _stats.total_requests > 0:
		hit_percent = int(_stats.cache_hits * 100 / _stats.total_requests)
	
	debug_print("- Cache hits: " + str(_stats.cache_hits) + " (" + str(hit_percent) + "%)")
	debug_print("- Cache misses: " + str(_stats.cache_misses) + " (" + str(100 - hit_percent) + "%)")
	
	var uptime = (Time.get_ticks_msec() - _stats.last_cache_clear) / 1000.0
	debug_print("- Time since last cache clear: " + str(int(uptime)) + " seconds")

# Utility debug print
func debug_print(message: String) -> void:
	if debug_mode:
		if has_dependency("DebugLogger"):
			var logger = get_dependency("DebugLogger")
			logger.debug("SeedManager", message)
		else:
			print("SeedManager: " + message)

# Get a consistent random value between min and max for a given object ID
# Use object_subid for different values from same object
func get_random_value(object_id: int, min_val: float, max_val: float, object_subid: int = 0) -> float:
	# Check for early calls during initialization
	if not is_inside_tree():
		# Give a deterministic but not cached value for early calls
		var hash_seed = _hash_combine(_current_seed, object_id + object_subid)
		var temp_rng = RandomNumberGenerator.new()
		temp_rng.seed = hash_seed
		return min_val + temp_rng.randf() * (max_val - min_val)
	
	# Update stats
	_stats.total_requests += 1
	
	# Try to get from cache first
	var cache_key = "value_%d_%d_%f_%f" % [object_id, object_subid, min_val, max_val]
	if enable_cache and _value_cache.has(cache_key):
		_stats.cache_hits += 1
		return _value_cache[cache_key]
	
	_stats.cache_misses += 1
	
	# Create a deterministic random value based on the seed and object ID
	var hash_seed = _hash_combine(_current_seed, object_id + object_subid)
	var temp_rng = RandomNumberGenerator.new()
	temp_rng.seed = hash_seed
	
	var result = min_val + temp_rng.randf() * (max_val - min_val)
	
	# Cache the result
	if enable_cache:
		_value_cache[cache_key] = result
		_clean_cache_if_needed()
	
	return result

# Get a random integer in a given range for an object
func get_random_int(object_id: int, min_val: int, max_val: int, object_subid: int = 0) -> int:
	# Check for early calls during initialization
	if not is_inside_tree():
		# Give a deterministic but not cached value for early calls
		var hash_seed = _hash_combine(_current_seed, object_id + object_subid)
		var temp_rng = RandomNumberGenerator.new()
		temp_rng.seed = hash_seed
		return temp_rng.randi_range(min_val, max_val)
	
	# Update stats
	_stats.total_requests += 1
	
	# Try to get from cache first
	var cache_key = "int_%d_%d_%d_%d" % [object_id, object_subid, min_val, max_val]
	if enable_cache and _value_cache.has(cache_key):
		_stats.cache_hits += 1
		return _value_cache[cache_key]
	
	_stats.cache_misses += 1
	
	var hash_seed = _hash_combine(_current_seed, object_id + object_subid)
	var temp_rng = RandomNumberGenerator.new()
	temp_rng.seed = hash_seed
	
	var result = temp_rng.randi_range(min_val, max_val)
	
	# Cache the result
	if enable_cache:
		_value_cache[cache_key] = result
		_clean_cache_if_needed()
	
	return result

# Get a random boolean based on probability
func get_random_bool(object_id: int, probability: float = 0.5, object_subid: int = 0) -> bool:
	# Check for early calls during initialization
	if not is_inside_tree():
		# Give a deterministic but not cached value for early calls
		var hash_seed = _hash_combine(_current_seed, object_id + object_subid)
		var temp_rng = RandomNumberGenerator.new()
		temp_rng.seed = hash_seed
		return temp_rng.randf() <= probability
	
	# Update stats
	_stats.total_requests += 1
	
	# Try to get from cache first
	var cache_key = "bool_%d_%d_%f" % [object_id, object_subid, probability]
	if enable_cache and _value_cache.has(cache_key):
		_stats.cache_hits += 1
		return _value_cache[cache_key]
	
	_stats.cache_misses += 1
	
	var hash_seed = _hash_combine(_current_seed, object_id + object_subid)
	var temp_rng = RandomNumberGenerator.new()
	temp_rng.seed = hash_seed
	
	var result = temp_rng.randf() <= probability
	
	# Cache the result
	if enable_cache:
		_value_cache[cache_key] = result
		_clean_cache_if_needed()
	
	return result

# Get a random point in a circle with given radius
func get_random_point_in_circle(object_id: int, radius: float, object_subid: int = 0) -> Vector2:
	# Check for early calls during initialization
	if not is_inside_tree():
		# Give a deterministic but not cached value for early calls
		var hash_seed = _hash_combine(_current_seed, object_id + object_subid)
		var temp_rng = RandomNumberGenerator.new()
		temp_rng.seed = hash_seed
		var angle = temp_rng.randf() * TAU
		var distance = sqrt(temp_rng.randf()) * radius
		return Vector2(cos(angle) * distance, sin(angle) * distance)
	
	# Update stats
	_stats.total_requests += 1
	
	# Try to get from cache first
	var cache_key = "circle_%d_%d_%f" % [object_id, object_subid, radius]
	if enable_cache and _value_cache.has(cache_key):
		_stats.cache_hits += 1
		return _value_cache[cache_key]
	
	_stats.cache_misses += 1
	
	var hash_seed = _hash_combine(_current_seed, object_id + object_subid)
	var temp_rng = RandomNumberGenerator.new()
	temp_rng.seed = hash_seed
	
	var angle = temp_rng.randf() * TAU  # Random angle in radians (0 to 2π)
	var distance = sqrt(temp_rng.randf()) * radius  # Square root for uniform distribution
	
	var result = Vector2(cos(angle) * distance, sin(angle) * distance)
	
	# Cache the result
	if enable_cache:
		_value_cache[cache_key] = result
		_clean_cache_if_needed()
	
	return result

# Get a 2D noise value for terrain/world generation
func get_2d_noise(x: float, y: float, scale: float = 1.0, octaves: int = 4, object_id: int = 0) -> float:
	# Get or create a noise generator for this object ID
	var noise = _get_noise_generator(object_id)
	
	# Configure noise properties
	noise.seed = _current_seed + object_id
	noise.octaves = octaves
	noise.persistence = 0.5
	noise.lacunarity = 2.0
	
	# Get the noise value
	return noise.get_noise_2d(x * scale, y * scale)

# Generate weighted random selection from array
func get_weighted_element(object_id: int, elements: Array, weights: Array = []) -> Variant:
	if elements.is_empty():
		return null
		
	if weights.is_empty():
		weights = Array()
		weights.resize(elements.size())
		for i in range(elements.size()):
			weights[i] = 1.0
	
	# Calculate total weight
	var total_weight = 0.0
	for w in weights:
		total_weight += w
	
	# Get random value
	var value = get_random_value(object_id, 0.0, total_weight)
	
	# Find the selected element
	var current_weight = 0.0
	for i in range(elements.size()):
		current_weight += weights[i]
		if value <= current_weight:
			return elements[i]
	
	# Fallback
	return elements[elements.size() - 1]

# Get a random value for visual effects.
# This doesn't need to be strictly deterministic across game restarts,
# but should be consistent within the current game session.
func get_visual_random_value(min_val: float, max_val: float) -> float:
	# Use a combination of the current game time and the game seed
	# This ensures visual variety but still produces consistent results in a session
	var time_seed = (Time.get_ticks_msec() / 100) % 10000  # Use only the last 10000 centiseconds
	return get_random_value(time_seed, min_val, max_val)

# Get a visual random Vector2 for effects, animations, etc.
func get_visual_random_vector(min_val: float, max_val: float) -> Vector2:
	var time_seed = (Time.get_ticks_msec() / 100) % 10000
	return Vector2(
		get_random_value(time_seed, min_val, max_val),
		get_random_value(time_seed + 1, min_val, max_val)
	)

# Deterministically shuffle an array using the seed
func shuffle_array(array: Array, object_id: int = 0) -> void:
	if array.size() <= 1:
		return
		
	# Fisher-Yates shuffle algorithm with deterministic randomization
	for i in range(array.size() - 1, 0, -1):
		var j = get_random_int(object_id + i, 0, i)
		
		# Swap elements
		var temp = array[i]
		array[i] = array[j]
		array[j] = temp

# Get a random element from an array
func choose(object_id: int, array: Array) -> Variant:
	if array.is_empty():
		return null
	
	var index = get_random_int(object_id, 0, array.size() - 1)
	return array[index]

# Generate multiple unique indices from a range
func unique_indices(object_id: int, count: int, max_index: int) -> Array:
	if count > max_index + 1:
		# Can't generate more unique indices than the range allows
		count = max_index + 1
	
	# Create an array of all possible indices
	var all_indices = []
	for i in range(max_index + 1):
		all_indices.append(i)
	
	# Shuffle the array deterministically
	shuffle_array(all_indices, object_id)
	
	# Return the first 'count' elements
	return all_indices.slice(0, count)

# Helper method to get/create a noise generator
func _get_noise_generator(object_id: int) -> FastNoiseLite:
	if not _noise_generators.has(object_id):
		var noise = FastNoiseLite.new()
		noise.seed = _current_seed + object_id
		_noise_generators[object_id] = noise
	
	return _noise_generators[object_id]

# Helper to clear caches
func _clear_caches() -> void:
	# Check for early calls during initialization
	if not is_inside_tree():
		# Defer until we're ready
		call_deferred("_clear_caches")
		return
	
	_value_cache.clear()
	_noise_generators.clear()
	
	# Reset cache statistics
	_stats.cache_hits = 0
	_stats.cache_misses = 0
	_stats.total_requests = 0
	_stats.last_cache_clear = Time.get_ticks_msec()
	
	if debug_mode:
		debug_print("Cleared caches due to seed change")
	
	# Try to clear texture cache if PlanetSpawnerBase exists
	# First try through DI, then fallback to direct access
	var planet_spawner = null
	if has_dependency("PlanetSpawnerBase"):
		planet_spawner = get_dependency("PlanetSpawnerBase")
	
	if planet_spawner and planet_spawner.has_method("clear_texture_cache"):
		planet_spawner.clear_texture_cache()

# Helper to clean cache if it gets too big
func _clean_cache_if_needed() -> void:
	if _value_cache.size() > _max_cache_size:
		# Simple approach: just clear the cache when it gets too big
		# A more sophisticated approach would be to implement an LRU cache
		_value_cache.clear()
		
		if debug_mode:
			debug_print("Cache size limit reached, cleared cache")
		
		_stats.last_cache_clear = Time.get_ticks_msec()

# Helper function to combine seed and object ID into a new hash
func _hash_combine(seed_value: int, object_id: int) -> int:
	return ((seed_value << 5) + seed_value) ^ object_id

# Generate a readable hash string from the seed
func _generate_seed_hash(seed_value: int) -> String:
	# Convert to a 6-character alphanumeric hash
	var characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # Omitting similar characters
	var hash_string = ""
	var temp_seed = seed_value
	
	for i in range(6):
		var index = temp_seed % characters.length()
		hash_string += characters[index]
		# Fix for integer division
		temp_seed = int(temp_seed / float(characters.length()))
	
	return hash_string
