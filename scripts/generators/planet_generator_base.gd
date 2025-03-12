extends RefCounted
class_name PlanetGeneratorBase

# Planet categories and themes
enum PlanetCategory { TERRAN, GASEOUS }

enum PlanetTheme {
	# Terran planets
	ARID, ICE, LAVA, LUSH, DESERT, ALPINE, OCEAN,
	# Gaseous planets
	JUPITER, SATURN, URANUS, NEPTUNE
}

# Base planet sizes
const PLANET_SIZE_TERRAN: int = 256
const PLANET_SIZE_GASEOUS: int = 512

# Size arrays for variation
const TERRAN_PLANET_SIZES: Array[int] = [256, 272, 298]
const GASEOUS_PLANET_SIZES: Array[int] = [512, 544, 576]

# Noise generation constants
const TERRAIN_OCTAVES: int = 4
const COLOR_VARIATION: float = 1.5
const CUBIC_RESOLUTION: int = 32

# Texture cache with expiration timestamps
static var texture_cache: Dictionary = {
	"terran": {},
	"gaseous": {},
	"atmospheres": {}
}
static var cache_timestamps: Dictionary = {
	"terran": {},
	"gaseous": {},
	"atmospheres": {}
}
static var last_cleanup_time: int = 0

# Instance variables
var cubic_lookup: PackedFloat32Array = PackedFloat32Array()
var noise_cache: Dictionary = {}

# Initialization
func _init() -> void:
	cubic_lookup.resize(CUBIC_RESOLUTION)
	for i in range(CUBIC_RESOLUTION):
		var t = float(i) / float(CUBIC_RESOLUTION - 1)
		cubic_lookup[i] = t * t * (3.0 - 2.0 * t)

# Get planet size based on seed and type
static func get_planet_size(seed_value: int, is_gaseous: bool = false) -> int:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var size_array = GASEOUS_PLANET_SIZES if is_gaseous else TERRAN_PLANET_SIZES
	var index = rng.randi() % size_array.size()
	
	return size_array[index]

# Get planet radius from size
static func get_planet_radius(size: int) -> float:
	return size * 0.5

# Get category for a theme
static func get_planet_category(theme: int) -> int:
	return PlanetCategory.GASEOUS if theme >= PlanetTheme.JUPITER else PlanetCategory.TERRAN

# Clean cache when it gets too large
static func clean_texture_cache() -> void:
	var current_time = Time.get_ticks_msec()
	
	# Only clean every 10 seconds
	if current_time - last_cleanup_time < 10000:
		return
		
	last_cleanup_time = current_time
	var max_cache_items = 30  # Reduced from 50
	var expire_time = 60000   # 1 minute expiration
	
	for category in ["terran", "gaseous", "atmospheres"]:
		if not texture_cache.has(category):
			continue
			
		# Find expired items
		var to_remove = []
		for key in texture_cache[category]:
			if current_time - cache_timestamps[category].get(key, 0) > expire_time:
				to_remove.append(key)
				
		# Remove oldest items if cache is too large
		if texture_cache[category].size() > max_cache_items:
			var overflow = texture_cache[category].size() - max_cache_items
			var oldest_keys = []
			
			# Find oldest items
			for key in texture_cache[category]:
				if to_remove.has(key):
					continue
					
				var timestamp = cache_timestamps[category].get(key, 0)
				var i = 0
				while i < oldest_keys.size() and timestamp > cache_timestamps[category].get(oldest_keys[i], 0):
					i += 1
					
				if i < overflow:
					oldest_keys.insert(i, key)
					if oldest_keys.size() > overflow:
						oldest_keys.pop_back()
			
			# Add oldest to removal list
			to_remove.append_array(oldest_keys)
		
		# Remove items
		for key in to_remove:
			texture_cache[category].erase(key)
			if cache_timestamps[category].has(key):
				cache_timestamps[category].erase(key)

# Get random value for a position based on seed
func get_random_seed(x: float, y: float, seed_value: int) -> float:
	# Use integer hash key for better performance
	var key = (int(x) << 16) | (int(y) & 0xFFFF)
	
	if noise_cache.has(key):
		return noise_cache[key]
	
	var rng = RandomNumberGenerator.new()
	rng.seed = hash([seed_value, x, y])
	var value = rng.randf()
	
	noise_cache[key] = value
	return value

# Get cubic interpolation value
func get_cubic(t: float) -> float:
	var index = int(t * (CUBIC_RESOLUTION - 1))
	index = clamp(index, 0, CUBIC_RESOLUTION - 1)
	return cubic_lookup[index]

# Generate coherent noise with cubic interpolation
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

# Generate fractal Brownian motion noise
func fbm(x: float, y: float, octaves: int, seed_value: int) -> float:
	var value = 0.0
	var amplitude = 0.5
	var frequency = 8.0
	
	for _i in range(octaves):
		value += noise(x * frequency, y * frequency, seed_value) * amplitude
		frequency *= 2.0
		amplitude *= 0.5
	
	return value

# Convert 2D coordinates to sphere mapping
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

# Create empty atmosphere placeholder
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
		1
	]

# Determine planet theme based on seed
func get_planet_theme(seed_value: int) -> int:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng.randi() % PlanetTheme.size()

# Get theme name based on ID
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

# Compatibility method for old code
static func get_planet_texture(seed_value: int) -> Array:
	var base = PlanetGeneratorBase.new()
	var theme = base.get_planet_theme(seed_value)
	var category = get_planet_category(theme)
	
	var cache_key = str(seed_value)
	var cache_category = "terran" if category == PlanetCategory.TERRAN else "gaseous"
	
	# Update cache access time and clean if needed
	var current_time = Time.get_ticks_msec()
	
	# Check cache
	if texture_cache.has(cache_category) and texture_cache[cache_category].has(cache_key):
		if cache_timestamps.has(cache_category):
			cache_timestamps[cache_category][cache_key] = current_time
		# FIX: Return proper array when using texture from cache
		return texture_cache[cache_category][cache_key]
	
	# Create appropriate generator
	var generator
	if category == PlanetCategory.TERRAN:
		generator = load("res://scripts/generators/planet_generator_terran.gd").new()
	else:
		generator = load("res://scripts/generators/planet_generator_gaseous.gd").new()
	
	var textures = generator.create_planet_texture(seed_value)
	
	# Cache result
	if not texture_cache.has(cache_category):
		texture_cache[cache_category] = {}
	if not cache_timestamps.has(cache_category):
		cache_timestamps[cache_category] = {}
		
	texture_cache[cache_category][cache_key] = textures
	cache_timestamps[cache_category][cache_key] = current_time
	
	# Clean cache if needed
	clean_texture_cache()
	
	return textures
