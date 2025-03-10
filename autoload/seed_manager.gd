# autoload/seed_manager.gd
# ========================
# Purpose:
#   Manages procedural generation seeding and provides deterministic randomization methods.
#   Ensures consistent procedural generation based on game seeds.
#   Now works with GameSettings for centralized seed management.
#
# Interface:
#   Signals:
#     - seed_changed(new_seed)
#
#   Seed Methods:
#     - set_seed(new_seed)
#     - set_random_seed()
#     - get_seed()
#     - get_seed_hash()
#
#   Randomization Methods:
#     - get_random_value(object_id, min_val, max_val, object_subid)
#     - get_random_int(object_id, min_val, max_val, object_subid)
#     - get_random_point_in_circle(object_id, radius, object_subid)
#     - get_2d_noise(x, y, scale, octaves, object_id)
#     - get_weighted_element(object_id, elements, weights)

extends Node

signal seed_changed(new_seed)

# Seed properties
var current_seed: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var seed_hash: String = ""
var game_settings: GameSettings = null

# Cache for deterministic values
var _noise_generators = {}
var _value_cache = {}
var _max_cache_size = 1000  # Limit the cache size

# Flags
var debug_mode: bool = false
var enable_cache: bool = true  # Can be toggled for memory optimization

func _ready() -> void:
	# Find GameSettings after a frame delay
	call_deferred("_find_game_settings")
	
	# Initialize with a random seed if none is set
	if current_seed == 0:
		set_random_seed()

func _find_game_settings() -> void:
	# Wait a frame to ensure the scene is loaded
	await get_tree().process_frame
	
	# Find GameSettings in the main scene
	var main_scene = get_tree().current_scene
	game_settings = main_scene.get_node_or_null("GameSettings")
	
	if game_settings:
		# Connect to GameSettings seed_changed signal
		if game_settings.is_connected("seed_changed", _on_game_settings_seed_changed):
			game_settings.disconnect("seed_changed", _on_game_settings_seed_changed)
		game_settings.connect("seed_changed", _on_game_settings_seed_changed)
		
		# Get seed from GameSettings
		var settings_seed = game_settings.get_seed()
		if settings_seed != 0 and settings_seed != current_seed:
			set_seed(settings_seed)
			
		# Use debug mode from settings
		debug_mode = game_settings.debug_mode
		
		if debug_mode:
			print("SeedManager: Connected to GameSettings")
	else:
		if debug_mode:
			print("SeedManager: GameSettings not found, using standalone mode")

func _on_game_settings_seed_changed(new_seed: int) -> void:
	# Update our seed when GameSettings seed changes
	set_seed(new_seed)

func _on_game_started() -> void:
	# Use GameSettings seed if available
	if game_settings:
		set_seed(game_settings.get_seed())
	
func set_seed(new_seed: int) -> void:
	# Store the old seed for history
	if current_seed != 0 and current_seed != new_seed:
		if debug_mode:
			print("SeedManager: Changed seed from %s to %s" % [current_seed, new_seed])
	
	current_seed = new_seed
	rng.seed = current_seed
	
	# Create a seed hash for saving/loading
	seed_hash = _generate_seed_hash(current_seed)
	
	# Clear caches when seed changes
	_clear_caches()
	
	# Notify all systems that depend on the seed
	seed_changed.emit(current_seed)
	
	# Update GameSettings if it exists and the seed came from elsewhere
	if game_settings and game_settings.get_seed() != current_seed:
		game_settings.set_seed(current_seed)
	
	if debug_mode:
		print("Seed set to: %s (hash: %s)" % [current_seed, seed_hash])

func set_random_seed() -> void:
	# Generate a new random seed
	randomize()
	var new_seed = randi()
	set_seed(new_seed)

func get_seed() -> int:
	# If GameSettings is available, prefer its seed
	if game_settings:
		var settings_seed = game_settings.get_seed()
		if settings_seed != current_seed:
			set_seed(settings_seed)
	return current_seed

func get_seed_hash() -> String:
	return seed_hash

# Get a consistent random value between min and max for a given object ID
# Use object_subid for different values from same object
func get_random_value(object_id: int, min_val: float, max_val: float, object_subid: int = 0) -> float:
	# First use GameSettings if available
	if game_settings and game_settings.has_method("get_random_value"):
		return game_settings.get_random_value(object_id, min_val, max_val, object_subid)
	
	# Try to get from cache first
	var cache_key = "value_%d_%d_%f_%f" % [object_id, object_subid, min_val, max_val]
	if enable_cache and _value_cache.has(cache_key):
		return _value_cache[cache_key]
	
	# Create a deterministic random value based on the seed and object ID
	var hash_seed = _hash_combine(current_seed, object_id + object_subid)
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
	# First use GameSettings if available
	if game_settings and game_settings.has_method("get_random_int"):
		return game_settings.get_random_int(object_id, min_val, max_val, object_subid)
	
	# Try to get from cache first
	var cache_key = "int_%d_%d_%d_%d" % [object_id, object_subid, min_val, max_val]
	if enable_cache and _value_cache.has(cache_key):
		return _value_cache[cache_key]
	
	var hash_seed = _hash_combine(current_seed, object_id + object_subid)
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
	# First use GameSettings if available
	if game_settings and game_settings.has_method("get_random_point_in_circle"):
		return game_settings.get_random_point_in_circle(object_id, radius, object_subid)
	
	# Try to get from cache first
	var cache_key = "circle_%d_%d_%f" % [object_id, object_subid, radius]
	if enable_cache and _value_cache.has(cache_key):
		return _value_cache[cache_key]
	
	var hash_seed = _hash_combine(current_seed, object_id + object_subid)
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
	noise.seed = current_seed + object_id
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
		noise.seed = current_seed + object_id
		_noise_generators[object_id] = noise
	
	return _noise_generators[object_id]

# Helper to clear caches
func _clear_caches() -> void:
	_value_cache.clear()
	_noise_generators.clear()

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
