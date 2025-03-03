# planet_generator.gd - Improved procedural planet generation system
extends RefCounted

# Represents different planetary types with unique geological characteristics
enum PlanetTheme {
	ARID,       # Desert-like, sandy colors
	ICE,        # Cold, bluish-white palette
	LAVA,       # Volcanic, red and orange hues
	LUSH,       # Green and blue, vegetation-like
	DESERT,     # Dry, sandy, with rock formations
	ALPINE,     # Mountain and snow-capped terrain with forests
	OCEAN       # Predominantly water-based world
}

# Fixed planet sizes - exactly what will be rendered, no scaling occurs
const PLANET_SIZE_LARGE: int = 256
const PLANET_RADIUS: float = 128.0  # Exactly half of the texture size

# Performance and quality settings
const TERRAIN_OCTAVES: int = 4   # Used for noise generation
const COLOR_VARIATION: float = 1.5  # Higher values create more color variety

# Cache for generated planets by seed
static var planet_texture_cache: Dictionary = {}

# Optimization: Precomputed lookup tables and caches
var cubic_lookup: Array = []
var noise_cache: Dictionary = {}
const CUBIC_RESOLUTION: int = 512

# Initialize the generator
func _init():
	# Initialize cubic lookup table for smooth interpolation
	cubic_lookup.resize(CUBIC_RESOLUTION)
	for i in range(CUBIC_RESOLUTION):
		var t = float(i) / (CUBIC_RESOLUTION - 1)
		cubic_lookup[i] = t * t * (3.0 - 2.0 * t)

# Get a cached texture or generate a new one
static func get_planet_texture(seed_value: int) -> Array:
	if planet_texture_cache.has(seed_value):
		return planet_texture_cache[seed_value]
	
	var generator = new()
	var textures = generator.create_planet_texture(seed_value)
	
	# Cache the texture
	planet_texture_cache[seed_value] = textures
	
	# Limit cache size to prevent memory issues
	if planet_texture_cache.size() > 50:
		var oldest_key = planet_texture_cache.keys()[0]
		planet_texture_cache.erase(oldest_key)
	
	return textures

# Get planet size - always returns PLANET_SIZE_LARGE (256)
func get_planet_size(_seed_value: int) -> int:
	# Always return the large size (256x256) for consistent planet rendering
	return PLANET_SIZE_LARGE

# Get planet theme based on seed
func get_planet_theme(seed_value: int) -> int:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng.randi() % PlanetTheme.size()

# Optimized pseudo-random number generation with caching
func get_random_seed(x: float, y: float, seed_value: int) -> float:
	# Create cache key
	var key = str(x) + "_" + str(y) + "_" + str(seed_value)
	if noise_cache.has(key):
		return noise_cache[key]
	
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(str(seed_value) + str(x) + str(y))
	var value = rng.randf()
	
	# Store in cache
	noise_cache[key] = value
	return value

# Get cubic interpolation from lookup table
func get_cubic(t: float) -> float:
	var index = int(t * (CUBIC_RESOLUTION - 1))
	index = clamp(index, 0, CUBIC_RESOLUTION - 1)
	return cubic_lookup[index]

# Optimized interpolated noise generation
func noise(x: float, y: float, seed_value: int) -> float:
	var ix = floor(x)
	var iy = floor(y)
	var fx = x - ix
	var fy = y - iy
	
	# Use precomputed lookup table for cubic interpolation
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

# Improved Fractal Brownian Motion with better quality control
func fbm(x: float, y: float, octaves: int, seed_value: int) -> float:
	var value = 0.0
	var amplitude = 0.5
	var frequency = 8.0
	
	for _i in range(octaves):
		value += noise(x * frequency, y * frequency, seed_value) * amplitude
		frequency *= 2.0
		amplitude *= 0.5
	
	return value

# Optimized spherical coordinate mapping with edge smoothing
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

# Generate enhanced color palettes for different planetary themes
func generate_planet_palette(theme: int, seed_value: int) -> PackedColorArray:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	match theme:
		PlanetTheme.ARID:
			return PackedColorArray([
				Color(0.90, 0.70, 0.40),  # Light sand
				Color(0.82, 0.58, 0.35),  # Light sand with red tint
				Color(0.75, 0.47, 0.30),  # Medium sand
				Color(0.70, 0.42, 0.25),  # Dark sand with red tint
				Color(0.63, 0.38, 0.22),  # Sandy base with red tint
				Color(0.53, 0.30, 0.16),  # Deep rocky terrain with red tint
				Color(0.40, 0.23, 0.12)   # Dark rocky ground with red tint
			])
		
		PlanetTheme.LAVA:
			return PackedColorArray([
				Color(1.0, 0.6, 0.0),     # Bright orange for lava lakes
				Color(0.9, 0.4, 0.05),    # Orange lava
				Color(0.8, 0.2, 0.05),    # Red-orange lava
				Color(0.7, 0.1, 0.05),    # Dark red lava
				Color(0.55, 0.08, 0.04),  # Deeper red lava
				Color(0.4, 0.06, 0.03),   # Very dark red terrain
				Color(0.25, 0.04, 0.02)   # Nearly black volcanic rock
			])
		
		PlanetTheme.LUSH:
			# Fixed palette for lush planets - more balanced greens and blues
			return PackedColorArray([
				Color(0.20, 0.70, 0.30),  # Bright vibrant green
				Color(0.18, 0.65, 0.25),  # Medium bright green  
				Color(0.15, 0.60, 0.20),  # Medium green
				Color(0.12, 0.55, 0.15),  # Forest green
				Color(0.10, 0.50, 0.10),  # Dark forest green
				Color(0.35, 0.50, 0.70),  # Light blue water
				Color(0.30, 0.45, 0.65),  # Medium blue water
				Color(0.25, 0.40, 0.60)   # Deeper blue water
			])
		
		PlanetTheme.ICE:
			return PackedColorArray([
				Color(0.98, 0.99, 1.0),   # Bright white ice
				Color(0.92, 0.97, 1.0),   # Bright white ice with blue tint
				Color(0.85, 0.92, 0.98),  # Very light blue ice
				Color(0.75, 0.85, 0.95),  # Light blue glacial
				Color(0.60, 0.75, 0.90),  # Deeper glacial blue
				Color(0.45, 0.65, 0.85),  # Deep ice
				Color(0.30, 0.50, 0.75)   # Glacial crevasses
			])
		
		PlanetTheme.DESERT:
			return PackedColorArray([
				Color(0.88, 0.72, 0.45),  # Light sand dunes
				Color(0.85, 0.68, 0.40),  # Light warm sand
				Color(0.80, 0.65, 0.38),  # Warm sand
				Color(0.75, 0.60, 0.35),  # Medium sand
				Color(0.70, 0.55, 0.30),  # Sandy plateaus
				Color(0.65, 0.50, 0.28),  # Sandy rock
				Color(0.60, 0.45, 0.25),  # Rocky outcrops
				Color(0.48, 0.35, 0.20)   # Deep desert terrain
			])
		
		PlanetTheme.ALPINE:
			return PackedColorArray([
				Color(0.98, 0.98, 0.98),  # Pure white snow
				Color(0.95, 0.95, 0.97),  # Off-white snow
				Color(0.90, 0.90, 0.95),  # Bright white snow
				Color(0.85, 0.85, 0.90),  # Light grey snow
				Color(0.80, 0.85, 0.80),  # Snow-forest transition
				Color(0.75, 0.85, 0.75),  # Snow-covered forests (white-green)
				Color(0.70, 0.80, 0.70),  # Light forests
				Color(0.65, 0.75, 0.65)   # Deeper forests
			])
		
		PlanetTheme.OCEAN:
			return PackedColorArray([
				Color(0.10, 0.35, 0.65),  # Deep ocean blue
				Color(0.15, 0.40, 0.70),  # Deep ocean
				Color(0.15, 0.45, 0.75),  # Mid-ocean blue
				Color(0.18, 0.50, 0.80),  # Medium ocean blue
				Color(0.20, 0.55, 0.85),  # Light ocean blue
				Color(0.25, 0.60, 0.88),  # Shallow ocean
				Color(0.30, 0.65, 0.90),  # Shallow water
				Color(0.40, 0.75, 0.95)   # Coastal waters
			])
		
		_:
			return PackedColorArray([
				Color(0.5, 0.5, 0.5),
				Color(0.6, 0.6, 0.6),
				Color(0.4, 0.4, 0.4),
				Color(0.7, 0.7, 0.7),
				Color(0.3, 0.3, 0.3)
			])

# Create empty atmosphere texture (1x1 transparent pixel)
func create_empty_atmosphere() -> Image:
	var empty_atmosphere = Image.create(1, 1, true, Image.FORMAT_RGBA8)
	empty_atmosphere.set_pixel(0, 0, Color(0, 0, 0, 0))
	return empty_atmosphere

# Improved planet texture creation with proper circular masking
func create_planet_texture(seed_value: int) -> Array:
	# Always use 256x256 pixels for planets
	var planet_size = PLANET_SIZE_LARGE
	
	# Create image at exact pixel resolution with alpha channel enabled
	var image = Image.create(planet_size, planet_size, true, Image.FORMAT_RGBA8)
	
	# Get theme for this planet
	var current_theme = get_planet_theme(seed_value)
	
	# Generate color palette for current theme
	var colors = generate_planet_palette(current_theme, seed_value)
	
	# Use exact radius - half of the texture size
	var planet_radius = PLANET_RADIUS
	
	# Create a small anti-aliasing band at the edge
	var aa_width = 1.5  # Anti-aliasing width in pixels
	var aa_width_normalized = aa_width / planet_radius
	
	# Create noise multiplier seeds for color variation
	var variation_seed_1 = seed_value + 12345
	var variation_seed_2 = seed_value + 67890
	
	# Precompute some values for optimization
	var color_size = colors.size() - 1
	var half_size = planet_size / 2.0
	var planet_size_minus_one = planet_size - 1
	
	# Generate planet surface with clean edge
	for y in range(planet_size):
		# Calculate normalized y coordinate (-0.5 to 0.5)
		var ny = float(y) / planet_size_minus_one
		var dy = ny - 0.5  # Distance from center in y
		
		for x in range(planet_size):
			# Calculate normalized x coordinate (-0.5 to 0.5)
			var nx = float(x) / planet_size_minus_one
			var dx = nx - 0.5  # Distance from center in x
			
			# Calculate distance from center (0 to 1.0)
			var dist_squared = dx * dx + dy * dy
			var dist = sqrt(dist_squared)
			var normalized_dist = dist * 2.0  # Now 0-1 represents 0 to radius
			
			# Skip pixels outside the planet radius
			if normalized_dist > 1.0:
				# Set fully transparent for outside pixels
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
				
			# Apply anti-aliasing at the edge
			var alpha = 1.0
			if normalized_dist > (1.0 - aa_width_normalized):
				alpha = 1.0 - (normalized_dist - (1.0 - aa_width_normalized)) / aa_width_normalized
				alpha = clamp(alpha, 0.0, 1.0)
			
			# Spherify coordinates for natural planetary mapping
			var sphere_uv = spherify(nx, ny)
			
			# Generate base noise - main terrain features
			var base_noise = fbm(sphere_uv.x, sphere_uv.y, TERRAIN_OCTAVES, seed_value)
			
			# Add detail variation for more interesting coloration
			var detail_variation_1 = fbm(sphere_uv.x * 3.0, sphere_uv.y * 3.0, 2, variation_seed_1) * 0.1
			var detail_variation_2 = fbm(sphere_uv.x * 5.0, sphere_uv.y * 5.0, 1, variation_seed_2) * 0.05
			
			# Combine noise for more color variety
			var combined_noise = base_noise + detail_variation_1 + detail_variation_2
			combined_noise = clamp(combined_noise * COLOR_VARIATION, 0.0, 1.0)
			
			# Color mapping with enhanced terrain variation
			var color_index = int(combined_noise * color_size)
			color_index = clamp(color_index, 0, color_size)
			
			# Final color with improved lighting
			var final_color = colors[color_index]
			
			# Add depth shading - better looking gradient 
			var edge_shade = 1.0 - pow(normalized_dist, 2) * 0.3
			final_color.r *= edge_shade
			final_color.g *= edge_shade
			final_color.b *= edge_shade
			
			# Apply alpha for clean edge
			final_color.a = alpha
			
			image.set_pixel(x, y, final_color)
	
	# Return the generated textures
	var empty_atmosphere = create_empty_atmosphere()
	
	return [
		ImageTexture.create_from_image(image),
		ImageTexture.create_from_image(empty_atmosphere),
		planet_size  # Return the exact planet size as well
	]
