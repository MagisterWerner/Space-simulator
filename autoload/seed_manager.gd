extends Node

signal seed_initialized
signal seed_changed(new_seed)

# Cache for deterministic values
var _noise_generators = {}
var _value_cache = {}
var _max_cache_size = 1000

# References and flags
var game_settings: GameSettings = null
var debug_mode: bool = false
var enable_cache: bool = true
var is_initialized: bool = false

# Seed management
const DEFAULT_SEED: int = 0
var _current_seed: int = DEFAULT_SEED

# Statistics
var _stats = {
	"cache_hits": 0,
	"cache_misses": 0,
	"total_requests": 0,
	"last_cache_clear": 0
}

func _ready() -> void:
	call_deferred("_find_game_settings")

func _find_game_settings() -> void:
	await get_tree().process_frame
	
	var main_scene = get_tree().current_scene
	game_settings = main_scene.get_node_or_null("GameSettings")
	
	if game_settings:
		# Connect to GameSettings signals
		if not game_settings.is_connected("seed_changed", _on_game_settings_seed_changed):
			game_settings.connect("seed_changed", _on_game_settings_seed_changed)
		
		if not game_settings.is_connected("debug_settings_changed", _on_debug_settings_changed):
			game_settings.connect("debug_settings_changed", _on_debug_settings_changed)
		
		if not game_settings._initialized:
			await game_settings.settings_initialized
		
		debug_mode = game_settings.debug_mode and game_settings.debug_seed_manager
		_current_seed = game_settings.get_seed()
	
	is_initialized = true
	seed_initialized.emit()
	_stats.last_cache_clear = Time.get_ticks_msec()

# Setting handlers
func _on_debug_settings_changed(debug_settings: Dictionary) -> void:
	debug_mode = debug_settings.get("master", false) and debug_settings.get("seed_manager", false)

func _on_game_settings_seed_changed(new_seed: int) -> void:
	_clear_caches()
	_current_seed = new_seed
	seed_changed.emit(new_seed)

# Seed management
func get_seed() -> int:
	return _current_seed

func set_seed(new_seed: int) -> void:
	if _current_seed == new_seed:
		return
		
	_current_seed = new_seed
	_clear_caches()
	seed_changed.emit(new_seed)

func get_seed_hash() -> String:
	if game_settings:
		return game_settings.seed_hash
	return _generate_seed_hash(_current_seed)

# Debug tools
func set_debug_mode(enable: bool) -> void:
	debug_mode = enable
	if debug_mode:
		print_cache_stats()

func print_cache_stats() -> void:
	if not debug_mode:
		return
		
	print("SeedManager: Cache size: " + str(_value_cache.size()) + "/" + str(_max_cache_size))
	print("SeedManager: Total requests: " + str(_stats.total_requests))
	
	var hit_percent = 0
	if _stats.total_requests > 0:
		hit_percent = int(_stats.cache_hits * 100 / _stats.total_requests)
	
	print("SeedManager: Cache hits: " + str(_stats.cache_hits) + " (" + str(hit_percent) + "%)")
	print("SeedManager: Cache misses: " + str(_stats.cache_misses) + " (" + str(100 - hit_percent) + "%)")
	
	var uptime = (Time.get_ticks_msec() - _stats.last_cache_clear) / 1000.0
	print("SeedManager: Time since last cache clear: " + str(int(uptime)) + " seconds")

# CORE RANDOM GENERATION METHODS

# Get a consistent random float value
func get_random_value(object_id: int, min_val: float, max_val: float, object_subid: int = 0) -> float:
	_stats.total_requests += 1
	
	# Simplified cache key
	var cache_key = str(object_id) + "_" + str(object_subid) + "_f_" + str(min_val) + "_" + str(max_val)
	
	if enable_cache and _value_cache.has(cache_key):
		_stats.cache_hits += 1
		return _value_cache[cache_key]
	
	_stats.cache_misses += 1
	
	# Optimized hash calculation
	var hash_seed = (_current_seed << 5) ^ object_id ^ object_subid
	var temp_rng = RandomNumberGenerator.new()
	temp_rng.seed = hash_seed
	
	var result = min_val + temp_rng.randf() * (max_val - min_val)
	
	if enable_cache:
		_value_cache[cache_key] = result
		if _value_cache.size() > _max_cache_size:
			_clear_caches()
	
	return result

# Get a random integer in a given range
func get_random_int(object_id: int, min_val: int, max_val: int, object_subid: int = 0) -> int:
	_stats.total_requests += 1
	
	var cache_key = str(object_id) + "_" + str(object_subid) + "_i_" + str(min_val) + "_" + str(max_val)
	
	if enable_cache and _value_cache.has(cache_key):
		_stats.cache_hits += 1
		return _value_cache[cache_key]
	
	_stats.cache_misses += 1
	
	var hash_seed = (_current_seed << 5) ^ object_id ^ object_subid
	var temp_rng = RandomNumberGenerator.new()
	temp_rng.seed = hash_seed
	
	var result = temp_rng.randi_range(min_val, max_val)
	
	if enable_cache:
		_value_cache[cache_key] = result
		if _value_cache.size() > _max_cache_size:
			_clear_caches()
	
	return result

# Get a random boolean based on probability
func get_random_bool(object_id: int, probability: float = 0.5, object_subid: int = 0) -> bool:
	_stats.total_requests += 1
	
	var cache_key = str(object_id) + "_" + str(object_subid) + "_b_" + str(probability)
	
	if enable_cache and _value_cache.has(cache_key):
		_stats.cache_hits += 1
		return _value_cache[cache_key]
	
	_stats.cache_misses += 1
	
	var hash_seed = (_current_seed << 5) ^ object_id ^ object_subid
	var temp_rng = RandomNumberGenerator.new()
	temp_rng.seed = hash_seed
	
	var result = temp_rng.randf() <= probability
	
	if enable_cache:
		_value_cache[cache_key] = result
		if _value_cache.size() > _max_cache_size:
			_clear_caches()
	
	return result

# Get a random point in a circle with given radius
func get_random_point_in_circle(object_id: int, radius: float, object_subid: int = 0) -> Vector2:
	_stats.total_requests += 1
	
	var cache_key = str(object_id) + "_" + str(object_subid) + "_c_" + str(radius)
	
	if enable_cache and _value_cache.has(cache_key):
		_stats.cache_hits += 1
		return _value_cache[cache_key]
	
	_stats.cache_misses += 1
	
	var hash_seed = (_current_seed << 5) ^ object_id ^ object_subid
	var temp_rng = RandomNumberGenerator.new()
	temp_rng.seed = hash_seed
	
	var angle = temp_rng.randf() * TAU
	var distance = sqrt(temp_rng.randf()) * radius
	
	var result = Vector2(cos(angle) * distance, sin(angle) * distance)
	
	if enable_cache:
		_value_cache[cache_key] = result
		if _value_cache.size() > _max_cache_size:
			_clear_caches()
	
	return result

# Get a 2D noise value for terrain generation
func get_2d_noise(x: float, y: float, scale: float = 1.0, octaves: int = 4, object_id: int = 0) -> float:
	var noise = _get_noise_generator(object_id)
	
	noise.seed = _current_seed + object_id
	noise.octaves = octaves
	noise.persistence = 0.5
	noise.lacunarity = 2.0
	
	return noise.get_noise_2d(x * scale, y * scale)

# UTILITY METHODS

# Generate weighted random selection from array
func get_weighted_element(object_id: int, elements: Array, weights: Array = []) -> Variant:
	if elements.is_empty():
		return null
		
	if weights.is_empty():
		weights = []
		weights.resize(elements.size())
		for i in range(elements.size()):
			weights[i] = 1.0
	
	var total_weight = 0.0
	for w in weights:
		total_weight += w
	
	var value = get_random_value(object_id, 0.0, total_weight)
	
	var current_weight = 0.0
	for i in range(elements.size()):
		current_weight += weights[i]
		if value <= current_weight:
			return elements[i]
	
	return elements.back()

# Get a random value for visual effects
func get_visual_random_value(min_val: float, max_val: float) -> float:
	var time_seed = (Time.get_ticks_msec() / 100) % 10000
	return get_random_value(time_seed, min_val, max_val)

# Get a visual random Vector2
func get_visual_random_vector(min_val: float, max_val: float) -> Vector2:
	var time_seed = (Time.get_ticks_msec() / 100) % 10000
	return Vector2(
		get_random_value(time_seed, min_val, max_val),
		get_random_value(time_seed + 1, min_val, max_val)
	)

# Deterministically shuffle an array
func shuffle_array(array: Array, object_id: int = 0) -> void:
	if array.size() <= 1:
		return
		
	# Fisher-Yates shuffle
	for i in range(array.size() - 1, 0, -1):
		var j = get_random_int(object_id + i, 0, i)
		
		# Swap
		var temp = array[i]
		array[i] = array[j]
		array[j] = temp

# INTERNAL HELPERS

# Get or create a noise generator
func _get_noise_generator(object_id: int) -> FastNoiseLite:
	if not _noise_generators.has(object_id):
		var noise = FastNoiseLite.new()
		noise.seed = _current_seed + object_id
		_noise_generators[object_id] = noise
	
	return _noise_generators[object_id]

# Clear caches
func _clear_caches() -> void:
	_value_cache.clear()
	_noise_generators.clear()
	
	# Reset statistics
	_stats.cache_hits = 0
	_stats.cache_misses = 0
	_stats.total_requests = 0
	_stats.last_cache_clear = Time.get_ticks_msec()
	
	# Attempt to clear texture cache using ClassDB instead of direct class access
	if get_tree().root.has_node("Main"):
		await get_tree().process_frame
		
		# Find any planet spawners in the scene and clear their caches
		var planet_spawners = get_tree().get_nodes_in_group("planet_spawners")
		for spawner in planet_spawners:
			if spawner.has_method("clear_texture_cache"):
				spawner.clear_texture_cache()
		
		# Try to find static method through ClassDB if no instances found
		if planet_spawners.is_empty():
			# Use a safer approach that doesn't rely on calling static methods directly
			if ClassDB.class_exists("PlanetSpawnerBase"):
				# If a static method exists, we can try to call it safely using a different approach
				# For now, just log that we found the class but couldn't call the method
				if debug_mode:
					print("SeedManager: Found PlanetSpawnerBase class but couldn't clear texture cache (no instances)")

# Generate a readable hash string from the seed
func _generate_seed_hash(seed_value: int) -> String:
	var characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var hash_string = ""
	var temp_seed = seed_value
	
	for i in range(6):
		var index = temp_seed % characters.length()
		hash_string += characters[index]
		temp_seed = int(temp_seed / float(characters.length()))
	
	return hash_string
