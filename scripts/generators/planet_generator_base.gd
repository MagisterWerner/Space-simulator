# scripts/generators/planet_generator_base.gd
# ==========================
# Purpose:
#   Base class for planet texture generators with common caching and utility functions
#   Provides a consistent interface for all planet type generators
#   Handles texture caching and resource optimization

extends RefCounted
class_name PlanetGeneratorBase

# Base size constants
const PLANET_SIZE_TERRAN: int = 256
const PLANET_SIZE_GASEOUS: int = 512

# Shared texture cache for all generators
# Static variables persist across all instances
static var texture_cache = {
	"planets": {}, # Planet textures 
	"atmospheres": {} # Atmosphere textures
}

# Maximum cache size before cleanup
const MAX_CACHE_SIZE: int = 50

# Virtual method for generating planet textures - to be overridden
func generate_planet_texture(_seed_value: int, _theme_id: int = -1) -> Array:
	push_error("PlanetGeneratorBase: generate_planet_texture must be overridden by subclasses")
	return []

# Generate a random theme based on seed
# Base implementation - may be overridden for specialized behavior
func get_random_theme(seed_value: int) -> int:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng.randi_range(0, 6) # Default range for terran planets (0-6)

# Clear the texture cache
static func clear_cache() -> void:
	texture_cache.planets.clear()
	texture_cache.atmospheres.clear()

# Prune the cache if it gets too large
static func cleanup_cache() -> void:
	var planets_keys = texture_cache.planets.keys()
	var atmosphere_keys = texture_cache.atmospheres.keys()
	
	if planets_keys.size() > MAX_CACHE_SIZE:
		for i in range(MAX_CACHE_SIZE / 4): # Remove 25% of cache
			if i < planets_keys.size():
				texture_cache.planets.erase(planets_keys[i])
	
	if atmosphere_keys.size() > MAX_CACHE_SIZE:
		for i in range(MAX_CACHE_SIZE / 4): # Remove 25% of cache
			if i < atmosphere_keys.size():
				texture_cache.atmospheres.erase(atmosphere_keys[i])

# Utility methods for noise generation that can be shared
func get_random_seed(x: float, y: float, seed_value: int, noise_cache: Dictionary) -> float:
	var key = str(x) + "_" + str(y) + "_" + str(seed_value)
	if noise_cache.has(key):
		return noise_cache[key]
	
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(str(seed_value) + str(x) + str(y))
	var value = rng.randf()
	
	noise_cache[key] = value
	return value

# Helper method for cubic interpolation
func cubic_interpolate(a: float, b: float, c: float, d: float, x: float) -> float:
	var p = (d - c) - (a - b)
	var q = (a - b) - p
	var r = c - a
	var s = b
	
	return p * x * x * x + q * x * x + r * x + s

# Spherical mapping for proper planet curvature
func spherify(x: float, y: float) -> Vector2:
	var centered_x = x * 2.0 - 1.0
	var centered_y = y * 2.0 - 1.0
	
	var length_squared = centered_x * centered_x + centered_y * centered_y
	
	if length_squared >= 1.0:
		return Vector2(x, y)
	
	var z = sqrt(1.0 - length_squared)
	var sphere_x = centered_x / (z + 1.0)
	var sphere_y = centered_y / (z + 1.0)
	
	return Vector2(
		(sphere_x + 1.0) * 0.5,
		(sphere_y + 1.0) * 0.5
	)

# Get a deterministic color for planets based on seed
func generate_base_color(seed_value: int, hue_range: Vector2 = Vector2(0, 1), saturation_range: Vector2 = Vector2(0.5, 1.0)) -> Color:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var h = hue_range.x + rng.randf() * (hue_range.y - hue_range.x)
	var s = saturation_range.x + rng.randf() * (saturation_range.y - saturation_range.x)
	var v = 0.7 + rng.randf() * 0.3 # Keep value (brightness) reasonably high
	
	return Color.from_hsv(h, s, v)

# Create an empty atmosphere placeholder when needed
func create_empty_atmosphere() -> Image:
	var empty_atmosphere = Image.create(1, 1, true, Image.FORMAT_RGBA8)
	empty_atmosphere.set_pixel(0, 0, Color(0, 0, 0, 0))
	return empty_atmosphere
