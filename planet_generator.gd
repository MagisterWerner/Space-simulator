# planet_generator.gd - Procedural planet generation system
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
const PLANET_SIZE_SMALL: int = 192
const PLANET_SIZE_LARGE: int = 256
const BASE_PLANET_RADIUS_FACTOR: float = 0.42

# Terrain Configuration
var terrain_size: float = 8.0  # Base terrain feature size
var terrain_octaves: int = 6   # Noise complexity
var light_origin: Vector2 = Vector2(0.39, 0.39)  # Light source position

# Atmosphere parameters
const ATMOSPHERE_THICKNESS: float = 1.0
const ATMOSPHERE_INTENSITY: float = 0.5

# Cache for generated planets by seed
static var planet_texture_cache: Dictionary = {}

# Initialize the generator
func _init():
	pass

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

# Get planet size based on seed - returns exactly PLANET_SIZE_SMALL or PLANET_SIZE_LARGE
func get_planet_size(seed_value: int) -> int:
	# Use the seed to deterministically choose one of the two fixed sizes
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# 50% chance of small or large planet
	if rng.randi() % 2 == 0:
		return PLANET_SIZE_SMALL
	else:
		return PLANET_SIZE_LARGE

# Get planet theme based on seed
func get_planet_theme(seed_value: int) -> int:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng.randi() % PlanetTheme.size()

# Calculate planet radius factor based on seed
func calculate_planet_radius_factor(seed_value: int) -> float:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# Generate a whole number percentage (100-150)
	var size_percentage = rng.randi_range(100, 150)
	
	# Apply to planet radius
	return BASE_PLANET_RADIUS_FACTOR * (float(size_percentage) / 100.0)

# Pseudo-random number generation with consistent geological behavior
func get_random_seed(x: float, y: float, seed_value: int) -> float:
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(str(seed_value) + str(x) + str(y))
	return rng.randf()

# Interpolated noise generation
func noise(x: float, y: float, seed_value: int) -> float:
	var ix = floor(x)
	var iy = floor(y)
	var fx = x - ix
	var fy = y - iy
	
	var cubic_x = fx * fx * (3.0 - 2.0 * fx)
	var cubic_y = fy * fy * (3.0 - 2.0 * fy)
	
	var a = get_random_seed(ix, iy, seed_value)
	var b = get_random_seed(ix + 1.0, iy, seed_value)
	var c = get_random_seed(ix, iy + 1.0, seed_value)
	var d = get_random_seed(ix + 1.0, iy + 1.0, seed_value)
	
	return lerp(
		lerp(a, b, cubic_x),
		lerp(c, d, cubic_x),
		cubic_y
	)

# Fractal Brownian Motion (fBm) terrain generation
func fbm(x: float, y: float, octaves: int, variation: float, seed_value: int) -> float:
	var value = 0.0
	var amplitude = 0.5
	var frequency = terrain_size * variation
	
	for _i in range(octaves):
		value += noise(x * frequency, y * frequency, seed_value) * amplitude
		frequency *= 2.0
		amplitude *= 0.5
	
	return value

# Sophisticated spherical coordinate mapping
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

# Generate color palettes for different planetary themes
func generate_planet_palette(theme: int, seed_value: int) -> PackedColorArray:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	match theme:
		PlanetTheme.ARID:
			return PackedColorArray([
				Color(0.82, 0.58, 0.35),  # Light sand with red tint
				Color(0.70, 0.42, 0.25),  # Dark sand with red tint
				Color(0.63, 0.38, 0.22),  # Sandy base with red tint
				Color(0.53, 0.30, 0.16),  # Deep rocky terrain with red tint
				Color(0.40, 0.23, 0.12)   # Dark rocky ground with red tint
			])
		
		PlanetTheme.LAVA:
			return PackedColorArray([
				Color(1.0, 0.6, 0.0),     # Single bright orange for lava lakes
				Color(0.7, 0.1, 0.05),    # Dark red lava
				Color(0.55, 0.08, 0.04),  # Deeper red lava
				Color(0.4, 0.06, 0.03),   # Very dark red terrain
				Color(0.25, 0.04, 0.02)   # Nearly black volcanic rock
			])
		
		PlanetTheme.LUSH:
			return PackedColorArray([
				Color(0.2, 0.7, 0.3),     # Bright vibrant green
				Color(0.1, 0.5, 0.1),     # Dark forest green
				Color(0.3, 0.5, 0.7),     # Blue water regions
				Color(0.25, 0.6, 0.25),   # Mid-tone vegetation
				Color(0.15, 0.4, 0.15)    # Deep forest shadow
			])
		
		PlanetTheme.ICE:
			return PackedColorArray([
				Color(0.92, 0.97, 1.0),   # Bright white ice
				Color(0.75, 0.85, 0.95),  # Light blue glacial
				Color(0.60, 0.75, 0.90),  # Deeper glacial blue
				Color(0.45, 0.65, 0.85),  # Deep ice
				Color(0.30, 0.50, 0.75)   # Glacial crevasses
			])
		
		PlanetTheme.DESERT:
			return PackedColorArray([
				Color(0.88, 0.72, 0.45),  # Light sand dunes
				Color(0.80, 0.65, 0.38),  # Warm sand
				Color(0.70, 0.55, 0.30),  # Sandy plateaus
				Color(0.60, 0.45, 0.25),  # Rocky outcrops
				Color(0.48, 0.35, 0.20)   # Deep desert terrain
			])
		
		PlanetTheme.ALPINE:
			return PackedColorArray([
				Color(0.98, 0.98, 0.98),  # Pure white snow
				Color(0.90, 0.90, 0.95),  # Bright white snow
				Color(0.85, 0.85, 0.90),  # Light grey snow
				Color(0.75, 0.85, 0.75),  # Snow-covered forests (white-green)
				Color(0.65, 0.75, 0.65)   # Light snow-dusted forests
			])
		
		PlanetTheme.OCEAN:
			return PackedColorArray([
				Color(0.10, 0.35, 0.65),  # Deep ocean blue
				Color(0.15, 0.45, 0.75),  # Mid-ocean blue
				Color(0.20, 0.55, 0.85),  # Light ocean blue
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

# Get atmosphere color with more realistic approach
func get_atmosphere_color(theme: int) -> Color:
	match theme:
		PlanetTheme.LUSH:
			return Color(0.35, 0.60, 0.90, 1.0)  # Blue with hint of green
		PlanetTheme.OCEAN:
			return Color(0.25, 0.55, 0.95, 1.0)  # Deep blue atmosphere
		PlanetTheme.ICE:
			return Color(0.65, 0.78, 0.95, 1.0)  # Pale blue atmosphere
		PlanetTheme.ALPINE:
			return Color(0.80, 0.82, 0.85, 1.0)  # Light grey with hint of blue
		PlanetTheme.LAVA:
			return Color(0.65, 0.15, 0.05, 1.0)  # Dark red atmosphere with slight orange tint
		PlanetTheme.DESERT:
			return Color(0.85, 0.65, 0.35, 1.0)  # Tan/brown atmosphere
		PlanetTheme.ARID:
			return Color(0.80, 0.45, 0.25, 1.0)  # Dusty red atmosphere
		_:
			return Color(0.60, 0.70, 0.90, 1.0)  # Default atmosphere

# Create planet texture with atmosphere rendering - ALWAYS at exact pixel size
func create_planet_texture(seed_value: int) -> Array:
	# Get either 192x192 or 256x256 pixels based on seed
	var planet_size = get_planet_size(seed_value)
	
	# Create images at exact pixel resolution
	var image = Image.create(planet_size, planet_size, false, Image.FORMAT_RGBA8)
	var atmosphere_image = Image.create(planet_size, planet_size, true, Image.FORMAT_RGBA8)
	
	# Get theme for this planet
	var current_theme = get_planet_theme(seed_value)
	
	# Generate color palette for current theme
	var colors = generate_planet_palette(current_theme, seed_value)
	var atmosphere_color = get_atmosphere_color(current_theme)
	
	# Calculate atmosphere parameters
	var planet_radius = calculate_planet_radius_factor(seed_value)
	var atmosphere_radius = planet_radius * (1.0 + ATMOSPHERE_THICKNESS)
	
	# Generate planet surface and atmosphere
	for x in range(planet_size):
		for y in range(planet_size):
			# Normalize coordinates
			var nx = float(x) / (planet_size - 1)
			var ny = float(y) / (planet_size - 1)
			
			# Calculate distance from center
			var dx = nx - 0.5
			var dy = ny - 0.5
			var d_circle = sqrt(dx * dx + dy * dy) * 2.0
			
			# Atmospheric rendering
			if d_circle > planet_radius and d_circle <= atmosphere_radius:
				var atmos_distance = (d_circle - planet_radius) / (atmosphere_radius - planet_radius)
				var atmos_alpha = pow(1.0 - atmos_distance, 4) * ATMOSPHERE_INTENSITY
				var pixel_atmosphere = atmosphere_color
				pixel_atmosphere.a = atmos_alpha * (1.0 - pow(atmos_distance, 0.5))
				atmosphere_image.set_pixel(x, y, pixel_atmosphere)
				continue
			
			# Skip pixels completely outside the atmosphere
			if d_circle > atmosphere_radius:
				continue
			
			# Spherify coordinates for natural planetary mapping
			var sphere_uv = spherify(nx, ny)
			
			# Generate multiple noise layers for complex terrain
			var base_noise = fbm(sphere_uv.x, sphere_uv.y, terrain_octaves, 1.0, seed_value)
			var detail_noise = fbm(sphere_uv.x * 2.0, sphere_uv.y * 2.0, max(2, terrain_octaves - 2), 1.5, seed_value + 10000)
			
			# Combine noise layers for rich terrain variation
			var combined_noise = base_noise * 0.7 + detail_noise * 0.3
			
			# Color mapping with terrain variation
			var color_index = int(combined_noise * colors.size())
			color_index = clamp(color_index, 0, colors.size() - 1)
			
			# Final color with terrain detail
			var final_color = colors[color_index]
			
			# Add depth and lighting simulation
			var edge_shade = 1.0 - pow(d_circle * 2, 2)
			final_color *= 0.8 + edge_shade * 0.2
			
			image.set_pixel(x, y, final_color)
	
	return [
		ImageTexture.create_from_image(image),
		ImageTexture.create_from_image(atmosphere_image),
		planet_size  # Return the exact planet size as well
	]
