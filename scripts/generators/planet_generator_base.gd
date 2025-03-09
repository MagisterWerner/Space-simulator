# scripts/generators/planet_generator_base.gd
# ==========================
# Purpose:
#   Base class for planet texture generators with shared functionality
#   Handles common noise generation, caching, and utility methods
#   Defines planet category and theme enums
#
# Dependencies:
#   - None
#
extends RefCounted
class_name PlanetGeneratorBase

# Shared category and theme enums - retained for compatibility
enum PlanetCategory {
	TERRAN,   # Rocky/solid surface planets (Earth-like, desert, ice, etc.)
	GASEOUS   # Gas planets without solid surface (gas giants, etc.)
}

enum PlanetTheme {
	# Terran planets
	ARID,
	ICE,
	LAVA,
	LUSH,
	DESERT,
	ALPINE,
	OCEAN,
	
	# Gaseous planets - UPDATED: Now individual types instead of just GAS_GIANT
	JUPITER,  # Jupiter-like (beige/tan tones)
	SATURN,   # Saturn-like (golden tones)
	URANUS,   # Uranus-like (cyan/teal tones)
	NEPTUNE   # Neptune-like (blue tones)
}

# Size constants (accessible to all derived classes)
const PLANET_SIZE_TERRAN: int = 256
const PLANET_SIZE_GASEOUS: int = 512  # Gas giants are twice as large
const PLANET_RADIUS_TERRAN: float = 128.0
const PLANET_RADIUS_GASEOUS: float = 256.0  # Larger radius for gaseous planets

# Noise generation constants
const TERRAIN_OCTAVES: int = 4
const COLOR_VARIATION: float = 1.5
const CUBIC_RESOLUTION: int = 32

# Shared static texture cache - accessed by all generator types
static var texture_cache: Dictionary = {
	"terran": {},
	"gaseous": {},
	"atmospheres": {}
}

# Instance variables
var cubic_lookup: Array = []
var noise_cache: Dictionary = {}

# Initialization
func _init() -> void:
	# Initialize cubic interpolation lookup table for smoother noise
	cubic_lookup.resize(CUBIC_RESOLUTION)
	for i in range(CUBIC_RESOLUTION):
		var t = float(i) / float(CUBIC_RESOLUTION - 1)
		cubic_lookup[i] = t * t * (3.0 - 2.0 * t)

# Get the category for a planet theme - kept as static method for compatibility
static func get_planet_category(theme: int) -> int:
	# Check if it's a gaseous planet theme
	if theme >= PlanetTheme.JUPITER:
		return PlanetCategory.GASEOUS
	return PlanetCategory.TERRAN

# Clean cache if it gets too large
static func clean_texture_cache() -> void:
	var max_cache_items = 50 # Maximum items per category
	
	for category in ["terran", "gaseous", "atmospheres"]:
		if texture_cache.has(category) and texture_cache[category].size() > max_cache_items:
			var keys_to_remove = texture_cache[category].keys().slice(0, int(max_cache_items / 4.0))
			for key in keys_to_remove:
				texture_cache[category].erase(key)

# Get a deterministic random value for a position
func get_random_seed(x: float, y: float, seed_value: int) -> float:
	var key = str(x) + "_" + str(y) + "_" + str(seed_value)
	if noise_cache.has(key):
		return noise_cache[key]
	
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(str(seed_value) + str(x) + str(y))
	var value = rng.randf()
	
	noise_cache[key] = value
	return value

# Get cubic interpolation value from the lookup table
func get_cubic(t: float) -> float:
	var index = int(t * (CUBIC_RESOLUTION - 1))
	index = clamp(index, 0, CUBIC_RESOLUTION - 1)
	return cubic_lookup[index]

# Generate smooth coherent noise
func noise(x: float, y: float, seed_value: int) -> float:
	var ix = floor(x)
	var iy = floor(y)
	var fx = x - ix
	var fy = y - iy
	
	var cubic_x = get_cubic(fx) 
	var cubic_y = get_cubic(fy)
	
	var a = get_random_seed(ix, iy, seed_value)
	var b = get_random_seed(ix + 1.0, iy, seed_value)
	var c = get_random_seed(ix, iy + 1.0, seed_value)
	var d = get_random_seed(ix + 1.0, iy + 1.0, seed_value)
	
	return lerp(
		lerp(a, b, cubic_x),
		lerp(c, d, cubic_x),
		cubic_y
	)

# Generate fractal Brownian motion noise with multiple octaves
func fbm(x: float, y: float, octaves: int, seed_value: int) -> float:
	var value = 0.0
	var amplitude = 0.5
	var frequency = 8.0
	
	for _i in range(octaves):
		value += noise(x * frequency, y * frequency, seed_value) * amplitude
		frequency *= 2.0
		amplitude *= 0.5
	
	return value

# Convert 2D coordinates to spherical mapping for proper planet curvature
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

# Create an empty atmosphere placeholder 
func create_empty_atmosphere() -> Image:
	var empty_atmosphere = Image.create(1, 1, true, Image.FORMAT_RGBA8)
	empty_atmosphere.set_pixel(0, 0, Color(0, 0, 0, 0))
	return empty_atmosphere

# Virtual method to be implemented by subclasses
func create_planet_texture(_seed_value: int) -> Array:
	push_error("PlanetGeneratorBase: create_planet_texture is a virtual method that should be overridden")
	return [
		ImageTexture.create_from_image(create_empty_atmosphere()),
		ImageTexture.create_from_image(create_empty_atmosphere()),
		1  # Default size
	]

# Shared method to determine planet theme based on seed
func get_planet_theme(seed_value: int) -> int:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng.randi() % PlanetTheme.size()

# Get theme name based on theme ID
static func get_theme_name(theme_id: int) -> String:
	match theme_id:
		PlanetTheme.ARID: return "Arid"
		PlanetTheme.ICE: return "Ice"
		PlanetTheme.LAVA: return "Lava"
		PlanetTheme.LUSH: return "Lush"
		PlanetTheme.DESERT: return "Desert"
		PlanetTheme.ALPINE: return "Alpine"
		PlanetTheme.OCEAN: return "Ocean"
		PlanetTheme.JUPITER: return "Jupiter-like"
		PlanetTheme.SATURN: return "Saturn-like"
		PlanetTheme.URANUS: return "Uranus-like"
		PlanetTheme.NEPTUNE: return "Neptune-like"
		_: return "Unknown"

# Compatibility method for older code that might call this directly
static func get_planet_texture(seed_value: int) -> Array:
	# First try to get from cache
	var theme = PlanetGeneratorBase.new().get_planet_theme(seed_value)
	var category = get_planet_category(theme)
	
	var cache_key = str(seed_value)
	var cache_category = "terran" if category == PlanetCategory.TERRAN else "gaseous"
	
	if texture_cache.has(cache_category) and texture_cache[cache_category].has(cache_key):
		return texture_cache[cache_category][cache_key]
	
	# Create appropriate generator and generate texture
	var generator
	if category == PlanetCategory.TERRAN:
		generator = PlanetGeneratorTerran.new()
	else:
		generator = PlanetGeneratorGaseous.new()
	
	var textures = generator.create_planet_texture(seed_value)
	
	# Cache the result
	if not texture_cache.has(cache_category):
		texture_cache[cache_category] = {}
	texture_cache[cache_category][cache_key] = textures
	
	# Clean cache if needed
	clean_texture_cache()
	
	return textures
