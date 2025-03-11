# scripts/utils/visual_randomizer.gd
# A helper class for generating deterministic random values for visual effects
# while maintaining seed consistency

extends Node
class_name VisualRandomizer

# Cache for already computed values
var _value_cache: Dictionary = {}
var _max_cache_size: int = 100

# Reference to SeedManager for consistent randomization
var _seed_manager = null

func _init() -> void:
	# Find SeedManager
	if Engine.has_singleton("SeedManager"):
		_seed_manager = Engine.get_singleton("SeedManager")
		
		# Wait for SeedManager to be initialized if needed
		if _seed_manager.has_method("is_initialized") and not _seed_manager.is_initialized:
			if _seed_manager.has_signal("seed_initialized"):
				await _seed_manager.seed_initialized

# Get a random floating point value within a range
func get_value(id: int, min_val: float, max_val: float, suffix: String = "") -> float:
	var cache_key = "float_%d_%s_%f_%f" % [id, suffix, min_val, max_val]
	
	# Return cached value if available
	if _value_cache.has(cache_key):
		return _value_cache[cache_key]
	
	var result = 0.0
	
	# Use SeedManager if available
	if _seed_manager:
		result = _seed_manager.get_random_value(id, min_val, max_val)
	else:
		# Fallback to deterministic but local random
		var temp_rng = RandomNumberGenerator.new()
		temp_rng.seed = id
		result = min_val + temp_rng.randf() * (max_val - min_val)
	
	# Cache result
	_value_cache[cache_key] = result
	_clean_cache_if_needed()
	return result

# Get a random integer within a range
func get_int(id: int, min_val: int, max_val: int, suffix: String = "") -> int:
	var cache_key = "int_%d_%s_%d_%d" % [id, suffix, min_val, max_val]
	
	# Return cached value if available
	if _value_cache.has(cache_key):
		return _value_cache[cache_key]
	
	var result = 0
	
	# Use SeedManager if available
	if _seed_manager:
		result = _seed_manager.get_random_int(id, min_val, max_val)
	else:
		# Fallback to deterministic but local random
		var temp_rng = RandomNumberGenerator.new()
		temp_rng.seed = id
		result = temp_rng.randi_range(min_val, max_val)
	
	# Cache result
	_value_cache[cache_key] = result
	_clean_cache_if_needed()
	return result

# Get a random boolean with a probability
func get_bool(id: int, probability: float = 0.5, suffix: String = "") -> bool:
	var cache_key = "bool_%d_%s_%f" % [id, suffix, probability]
	
	# Return cached value if available
	if _value_cache.has(cache_key):
		return _value_cache[cache_key]
	
	var result = false
	
	# Use SeedManager if available
	if _seed_manager:
		result = _seed_manager.get_random_value(id, 0.0, 1.0) <= probability
	else:
		# Fallback to deterministic but local random
		var temp_rng = RandomNumberGenerator.new()
		temp_rng.seed = id
		result = temp_rng.randf() <= probability
	
	# Cache result
	_value_cache[cache_key] = result
	_clean_cache_if_needed()
	return result

# Get a random point in a circle
func get_point_in_circle(id: int, radius: float, suffix: String = "") -> Vector2:
	var cache_key = "circle_%d_%s_%f" % [id, suffix, radius]
	
	# Return cached value if available
	if _value_cache.has(cache_key):
		return _value_cache[cache_key]
	
	var result = Vector2.ZERO
	
	# Use SeedManager if available
	if _seed_manager:
		result = _seed_manager.get_random_point_in_circle(id, radius)
	else:
		# Fallback to deterministic but local random
		var temp_rng = RandomNumberGenerator.new()
		temp_rng.seed = id
		var angle = temp_rng.randf() * TAU
		var distance = sqrt(temp_rng.randf()) * radius
		result = Vector2(cos(angle) * distance, sin(angle) * distance)
	
	# Cache result
	_value_cache[cache_key] = result
	_clean_cache_if_needed()
	return result

# Get a random element from an array
func get_random_element(id: int, array: Array, suffix: String = "") -> Variant:
	if array.is_empty():
		return null
	
	if array.size() == 1:
		return array[0]
	
	var index = get_int(id, 0, array.size() - 1, suffix)
	return array[index]

# Get a random color with optional parameters
func get_random_color(id: int, hue_min: float = 0.0, hue_max: float = 1.0, 
					  saturation: float = 1.0, value: float = 1.0, 
					  alpha: float = 1.0, suffix: String = "") -> Color:
	var h = get_value(id, hue_min, hue_max, suffix + "hue")
	return Color.from_hsv(h, saturation, value, alpha)

# Clear the cache (e.g., when changing scenes or when the cache gets too large)
func clear_cache() -> void:
	_value_cache.clear()

# Internal method: clean the cache if it gets too large
func _clean_cache_if_needed() -> void:
	if _value_cache.size() > _max_cache_size:
		clear_cache()
