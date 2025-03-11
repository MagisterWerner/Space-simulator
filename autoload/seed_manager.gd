# autoload/seed_manager.gd
# ========================
# Purpose:
#   Provides deterministic randomization methods using the game seed.
#   Ensures consistent procedural generation based on GameSettings' seed.

extends Node

signal seed_initialized
signal seed_changed(new_seed)

# Cache for deterministic values
var _noise_generators = {}
var _value_cache = {}
var _max_cache_size = 1000  # Limit the cache size

# Reference to GameSettings
var game_settings: GameSettings = null

# Flags
var debug_mode: bool = false
var enable_cache: bool = true  # Can be toggled for memory optimization
var is_initialized: bool = false

# Default seed to use if GameSettings is not available
const DEFAULT_SEED = 0
var _current_seed: int = DEFAULT_SEED

func _ready() -> void:
	# Find GameSettings after a frame delay
	call_deferred("_find_game_settings")

func _find_game_settings() -> void:
	# Wait a frame to ensure the scene is loaded
	await get_tree().process_frame
	
	# Find GameSettings in the main scene
	var main_scene = get_tree().current_scene
	game_settings = main_scene.get_node_or_null("GameSettings")
	
	if game_settings:
		# Connect to GameSettings seed_changed signal
		if not game_settings.is_connected("seed_changed", _on_game_settings_seed_changed):
			game_settings.connect("seed_changed", _on_game_settings_seed_changed)
		
		# Wait for GameSettings to be fully initialized if needed
		if not game_settings._initialized:
			await game_settings.settings_initialized
		
		# Use debug mode from settings
		debug_mode = game_settings.debug_mode
		
		# Get the seed from GameSettings
		_current_seed = game_settings.get_seed()
		
		if debug_mode:
			print("SeedManager: Connected to GameSettings, using seed:", _current_seed)
	else:
		if debug_mode:
			print("SeedManager: GameSettings not found, using default seed")
	
	# Mark as initialized and emit signal
	is_initialized = true
	seed_initialized.emit()

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
	if game_settings:
		return game_settings.seed_hash
	return _generate_seed_hash(_current_seed)

# Get a consistent random value between min and max for a given object ID
# Use object_subid for different values from same object
func get_random_value(object_id: int, min_val: float, max_val: float, object_subid: int = 0) -> float:
	# Try to get from cache first
	var cache_key = "value_%d_%d_%f_%f" % [object_id, object_subid, min_val, max_val]
	if enable_cache and _value_cache.has(cache_key):
		return _value_cache[cache_key]
	
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
	# Try to get from cache first
	var cache_key = "int_%d_%d_%d_%d" % [object_id, object_subid, min_val, max_val]
	if enable_cache and _value_cache.has(cache_key):
		return _value_cache[cache_key]
	
	var hash_seed = _hash_combine(_current_seed, object_id + object_subid)
	var temp_rng = RandomNumberGenerator.new()
	temp_rng.seed = hash_seed
	
	var result = temp_rng.randi_range(min_val, max_val)
	
	# Cache the result
	if enable_cache:
		_value_cache[cache_key] = result
		_clean_cache_if_needed()
	
	return result

# Get a random point in a circle with given radius
func get_random_point_in_circle(object_id: int, radius: float, object_subid: int = 0) -> Vector2:
	# Try to get from cache first
	var cache_key = "circle_%d_%d_%f" % [object_id, object_subid, radius]
	if enable_cache and _value_cache.has(cache_key):
		return _value_cache[cache_key]
	
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

# Helper method to get/create a noise generator
func _get_noise_generator(object_id: int) -> FastNoiseLite:
	if not _noise_generators.has(object_id):
		var noise = FastNoiseLite.new()
		noise.seed = _current_seed + object_id
		_noise_generators[object_id] = noise
	
	return _noise_generators[object_id]

# Helper to clear caches
func _clear_caches() -> void:
	_value_cache.clear()
	_noise_generators.clear()
	
	if debug_mode:
		print("SeedManager: Cleared caches due to seed change")
	
	# Also trigger a clear of the texture cache in PlanetSpawnerBase
	if get_tree().root.has_node("Main"):
		# Wait one frame to ensure everything is loaded
		await get_tree().process_frame
		
		# Call the static method to clear the texture cache
		PlanetSpawnerBase.clear_texture_cache()

# Helper to clean cache if it gets too big
func _clean_cache_if_needed() -> void:
	if _value_cache.size() > _max_cache_size:
		# Simple approach: just clear the cache when it gets too big
		# A more sophisticated approach would be to implement an LRU cache
		_value_cache.clear()

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
