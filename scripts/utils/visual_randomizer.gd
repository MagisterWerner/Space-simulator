extends Node
class_name VisualRandomizer

var _value_cache := {}
var _max_cache_size := 100
var _seed_manager = null

func _init() -> void:
	if Engine.has_singleton("SeedManager"):
		_seed_manager = Engine.get_singleton("SeedManager")
		if _seed_manager.has_method("is_initialized") and not _seed_manager.is_initialized:
			if _seed_manager.has_signal("seed_initialized"):
				await _seed_manager.seed_initialized

func get_value(id: int, min_val: float, max_val: float, suffix: String = "") -> float:
	var cache_key := "f%d%s%.1f%.1f" % [id, suffix, min_val, max_val]
	if _value_cache.has(cache_key):
		return _value_cache[cache_key]
	
	var result: float
	if _seed_manager:
		result = _seed_manager.get_random_value(id, min_val, max_val)
	else:
		result = _fallback_random(id, min_val, max_val)
	
	_value_cache[cache_key] = result
	_clean_cache_if_needed()
	return result

func get_int(id: int, min_val: int, max_val: int, suffix: String = "") -> int:
	var cache_key := "i%d%s%d%d" % [id, suffix, min_val, max_val]
	if _value_cache.has(cache_key):
		return _value_cache[cache_key]
	
	var result: int
	if _seed_manager:
		result = _seed_manager.get_random_int(id, min_val, max_val)
	else:
		result = _fallback_random_int(id, min_val, max_val)
	
	_value_cache[cache_key] = result
	_clean_cache_if_needed()
	return result

func get_bool(id: int, probability: float = 0.5, suffix: String = "") -> bool:
	var cache_key := "b%d%s%.2f" % [id, suffix, probability]
	if _value_cache.has(cache_key):
		return _value_cache[cache_key]
	
	var result: bool
	if _seed_manager:
		result = _seed_manager.get_random_value(id, 0.0, 1.0) <= probability
	else:
		var temp_rng := RandomNumberGenerator.new()
		temp_rng.seed = id
		result = temp_rng.randf() <= probability
	
	_value_cache[cache_key] = result
	_clean_cache_if_needed()
	return result

func get_point_in_circle(id: int, radius: float, suffix: String = "") -> Vector2:
	var cache_key := "c%d%s%.1f" % [id, suffix, radius]
	if _value_cache.has(cache_key):
		return _value_cache[cache_key]
	
	var result: Vector2
	if _seed_manager:
		result = _seed_manager.get_random_point_in_circle(id, radius)
	else:
		var temp_rng := RandomNumberGenerator.new()
		temp_rng.seed = id
		var angle := temp_rng.randf() * TAU
		var distance := sqrt(temp_rng.randf()) * radius
		result = Vector2(cos(angle) * distance, sin(angle) * distance)
	
	_value_cache[cache_key] = result
	_clean_cache_if_needed()
	return result

# Get a random element from an array with deterministic behavior
func get_random_element(id: int, array: Array, suffix: String = ""):
	if array.is_empty():
		return null
	
	if array.size() == 1:
		return array[0]
	
	var index := get_int(id, 0, array.size() - 1, suffix)
	return array[index]

# Generate a random color with deterministic behavior
func get_random_color(id: int, hue_min: float = 0.0, hue_max: float = 1.0, 
					  saturation: float = 1.0, value: float = 1.0, 
					  alpha: float = 1.0, suffix: String = "") -> Color:
	var h := get_value(id, hue_min, hue_max, suffix + "h")
	return Color.from_hsv(h, saturation, value, alpha)

# Centralized fallback random functions to reduce code duplication
func _fallback_random(id: int, min_val: float, max_val: float) -> float:
	var temp_rng := RandomNumberGenerator.new()
	temp_rng.seed = id
	return min_val + temp_rng.randf() * (max_val - min_val)

func _fallback_random_int(id: int, min_val: int, max_val: int) -> int:
	var temp_rng := RandomNumberGenerator.new()
	temp_rng.seed = id
	return temp_rng.randi_range(min_val, max_val)

# Cache management
func clear_cache() -> void:
	_value_cache.clear()

func _clean_cache_if_needed() -> void:
	if _value_cache.size() > _max_cache_size:
		clear_cache()
