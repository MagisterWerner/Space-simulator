# scripts/generators/planet_generator.gd
# ==========================
# Purpose:
#   Procedural planet texture generator with support for various planet types
#   Handles generation of both terran and gaseous planets with distinctive themes
#   Creates detailed planet textures with complex noise patterns and features
#   Generates pixel-perfect edges (no anti-aliasing)
#
# Interface:
#   - get_planet_texture(seed_value): Gets cached or generates new planet texture
#   - get_planet_theme(seed_value): Determines planet theme based on seed
#   - get_planet_category(theme): Returns planet category (TERRAN or GASEOUS)
#   - create_planet_texture(seed_value): Creates planet texture from scratch
#
# Dependencies:
#   - None
#
extends RefCounted
class_name PlanetGenerator

# Main planet category enum
enum PlanetCategory {
	TERRAN,   # Rocky/solid surface planets (Earth-like, desert, ice, etc.)
	GASEOUS   # Gas planets without solid surface (gas giants, etc.)
}

# Specific planet themes within categories
enum PlanetTheme {
	# Terran planets
	ARID,
	ICE,
	LAVA,
	LUSH,
	DESERT,
	ALPINE,
	OCEAN,
	
	# Gaseous planets
	GAS_GIANT  # Currently the only gaseous type
}

# Size constants
const PLANET_SIZE_TERRAN: int = 256
const PLANET_SIZE_GASEOUS: int = 512  # Gas giants are twice as large
const PLANET_RADIUS_TERRAN: float = 128.0
const PLANET_RADIUS_GASEOUS: float = 256.0  # Larger radius for gaseous planets

# Noise generation constants
const TERRAIN_OCTAVES: int = 4
const COLOR_VARIATION: float = 1.5

# Gas giant specific constants
const GAS_GIANT_BANDS: int = 12         # Number of primary bands
const GAS_GIANT_BAND_NOISE: float = 0.5  # How noisy the bands are
const GAS_GIANT_FLOW: float = 2.0       # How much the bands "flow" horizontally

# Static texture cache to avoid regenerating the same planets
static var planet_texture_cache: Dictionary = {}

# Lookup tables and caches for performance
var cubic_lookup: Array = []
var noise_cache: Dictionary = {}
const CUBIC_RESOLUTION: int = 32

func _init():
	# Initialize cubic interpolation lookup table for smoother noise
	cubic_lookup.resize(CUBIC_RESOLUTION)
	for i in range(CUBIC_RESOLUTION):
		var t = float(i) / (CUBIC_RESOLUTION - 1)
		cubic_lookup[i] = t * t * (3.0 - 2.0 * t)

# Get the category for a planet theme
static func get_planet_category(theme: int) -> int:
	# Currently only GAS_GIANT is GASEOUS, everything else is TERRAN
	if theme == PlanetTheme.GAS_GIANT:
		return PlanetCategory.GASEOUS
	return PlanetCategory.TERRAN

# Get a cached planet texture or generate a new one
static func get_planet_texture(seed_value: int) -> Array:
	if planet_texture_cache.has(seed_value):
		return planet_texture_cache[seed_value]
	
	var generator = new()
	var textures = generator.create_planet_texture(seed_value)
	
	planet_texture_cache[seed_value] = textures
	
	# Clean cache if it gets too large
	if planet_texture_cache.size() > 50:
		var oldest_key = planet_texture_cache.keys()[0]
		planet_texture_cache.erase(oldest_key)
	
	return textures

# Get the size of a planet based on seed and theme
func get_planet_size(seed_value: int) -> int:
	var theme = get_planet_theme(seed_value)
	var category = get_planet_category(theme)
	return PLANET_SIZE_GASEOUS if category == PlanetCategory.GASEOUS else PLANET_SIZE_TERRAN

# Determine the planet theme based on seed
func get_planet_theme(seed_value: int) -> int:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng.randi() % PlanetTheme.size()

# Generate a planet theme for a specific category
func get_themed_planet_for_category(seed_value: int, category: int) -> int:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	if category == PlanetCategory.GASEOUS:
		# Currently only GAS_GIANT is gaseous
		return PlanetTheme.GAS_GIANT
	else:
		# For TERRAN, pick any theme except GAS_GIANT
		var theme = rng.randi() % (PlanetTheme.GAS_GIANT)
		return theme

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

# Generate gas giant band pattern
func generate_gas_giant_band(y_coord: float, seed_value: int) -> float:
	# Create primary band structure
	var primary_bands = sin(y_coord * GAS_GIANT_BANDS * PI)
	
	# Add noise to make bands irregular
	var noise_seed1 = seed_value + 12345
	var noise_seed2 = seed_value + 54321
	
	var noise_x = y_coord * 5.0
	var noise_y = y_coord * 2.5
	
	var band_noise = fbm(noise_x, noise_y, 2, noise_seed1) * GAS_GIANT_BAND_NOISE
	
	# Create flow effect (horizontal distortion)
	var flow_x = y_coord * 3.0
	var flow_noise = fbm(flow_x, 0.5, 2, noise_seed2) * GAS_GIANT_FLOW
	
	return (primary_bands + band_noise + flow_noise) * 0.5 + 0.5

# Generate appropriate color palette for each planet theme
func generate_planet_palette(theme: int, seed_value: int) -> PackedColorArray:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	match theme:
		PlanetTheme.GAS_GIANT:
			# Extract gas giant type from the higher bits of the seed
			# This ensures we use the type encoded by planet.gd
			var gas_giant_type = (seed_value / 10000) % 4
			
			match gas_giant_type:
				0:  # Jupiter-like (balanced beige/tan/brown tones)
					return PackedColorArray([
						Color(0.83, 0.78, 0.65),  # Light beige
						Color(0.80, 0.73, 0.60),  # Beige
						Color(0.77, 0.68, 0.55),  # Darker beige
						Color(0.74, 0.63, 0.50),  # Light tan
						Color(0.71, 0.58, 0.45),  # Tan
						Color(0.68, 0.53, 0.40),  # Dark tan
						Color(0.65, 0.48, 0.35),  # Light brown
						Color(0.62, 0.43, 0.30)   # Brown
					])
				1:  # Saturn-like (soft golden/yellow tones)
					return PackedColorArray([
						Color(0.85, 0.82, 0.70),  # Pale gold
						Color(0.83, 0.80, 0.66),  # Light gold
						Color(0.81, 0.78, 0.62),  # Gold
						Color(0.79, 0.76, 0.58),  # Muted gold
						Color(0.77, 0.74, 0.54),  # Darker gold
						Color(0.75, 0.72, 0.50),  # Dusky gold
						Color(0.73, 0.70, 0.46),  # Golden tan
						Color(0.71, 0.68, 0.42)   # Dark golden tan
					])
				2:  # Neptune-like (balanced blue tones)
					return PackedColorArray([
						Color(0.60, 0.75, 0.85),  # Light blue
						Color(0.55, 0.72, 0.83),  # Sky blue
						Color(0.50, 0.69, 0.81),  # Azure
						Color(0.45, 0.66, 0.79),  # Medium blue
						Color(0.40, 0.63, 0.77),  # Blue
						Color(0.35, 0.60, 0.75),  # Deep blue
						Color(0.30, 0.57, 0.73),  # Dark blue
						Color(0.25, 0.54, 0.71)   # Navy blue
					])
				3:  # Exotic gas giant (subtle purple/lavender tones)
					return PackedColorArray([
						Color(0.75, 0.70, 0.85),  # Very light lavender
						Color(0.70, 0.65, 0.83),  # Light lavender
						Color(0.65, 0.60, 0.81),  # Lavender
						Color(0.60, 0.55, 0.79),  # Medium lavender
						Color(0.55, 0.50, 0.77),  # Dusky lavender
						Color(0.50, 0.45, 0.75),  # Light purple
						Color(0.45, 0.40, 0.73),  # Purple
						Color(0.40, 0.35, 0.71)   # Deep purple
					])
				_:  # Fallback
					return PackedColorArray([
						Color(0.83, 0.78, 0.65),
						Color(0.77, 0.68, 0.55),
						Color(0.71, 0.58, 0.45),
						Color(0.65, 0.48, 0.35),
					])
		
		PlanetTheme.ARID:
			return PackedColorArray([
				Color(0.90, 0.70, 0.40),
				Color(0.82, 0.58, 0.35),
				Color(0.75, 0.47, 0.30),
				Color(0.70, 0.42, 0.25),
				Color(0.63, 0.38, 0.22),
				Color(0.53, 0.30, 0.16),
				Color(0.40, 0.23, 0.12)
			])
		
		PlanetTheme.LAVA:
			return PackedColorArray([
				Color(1.0, 0.6, 0.0),
				Color(0.9, 0.4, 0.05),
				Color(0.8, 0.2, 0.05),
				Color(0.7, 0.1, 0.05),
				Color(0.55, 0.08, 0.04),
				Color(0.4, 0.06, 0.03),
				Color(0.25, 0.04, 0.02)
			])
		
		PlanetTheme.LUSH:
			return PackedColorArray([
				Color(0.20, 0.70, 0.30),
				Color(0.18, 0.65, 0.25),
				Color(0.15, 0.60, 0.20),
				Color(0.12, 0.55, 0.15),
				Color(0.10, 0.50, 0.10),
				Color(0.35, 0.50, 0.70),
				Color(0.30, 0.45, 0.65),
				Color(0.25, 0.40, 0.60)
			])
		
		PlanetTheme.ICE:
			return PackedColorArray([
				Color(0.98, 0.99, 1.0),
				Color(0.92, 0.97, 1.0),
				Color(0.85, 0.92, 0.98),
				Color(0.75, 0.85, 0.95),
				Color(0.60, 0.75, 0.90),
				Color(0.45, 0.65, 0.85),
				Color(0.30, 0.50, 0.75)
			])
		
		PlanetTheme.DESERT:
			return PackedColorArray([
				Color(0.88, 0.72, 0.45),
				Color(0.85, 0.68, 0.40),
				Color(0.80, 0.65, 0.38),
				Color(0.75, 0.60, 0.35),
				Color(0.70, 0.55, 0.30),
				Color(0.65, 0.50, 0.28),
				Color(0.60, 0.45, 0.25),
				Color(0.48, 0.35, 0.20)
			])
		
		PlanetTheme.ALPINE:
			return PackedColorArray([
				Color(0.98, 0.98, 0.98),
				Color(0.95, 0.95, 0.97),
				Color(0.90, 0.90, 0.95),
				Color(0.85, 0.85, 0.90),
				Color(0.80, 0.85, 0.80),
				Color(0.75, 0.85, 0.75),
				Color(0.70, 0.80, 0.70),
				Color(0.65, 0.75, 0.65)
			])
		
		PlanetTheme.OCEAN:
			return PackedColorArray([
				Color(0.10, 0.35, 0.65),
				Color(0.15, 0.40, 0.70),
				Color(0.15, 0.45, 0.75),
				Color(0.18, 0.50, 0.80),
				Color(0.20, 0.55, 0.85),
				Color(0.25, 0.60, 0.88),
				Color(0.30, 0.65, 0.90),
				Color(0.40, 0.75, 0.95)
			])
		
		_:
			return PackedColorArray([
				Color(0.5, 0.5, 0.5),
				Color(0.6, 0.6, 0.6),
				Color(0.4, 0.4, 0.4),
				Color(0.7, 0.7, 0.7),
				Color(0.3, 0.3, 0.3)
			])

# Create an empty atmosphere placeholder
func create_empty_atmosphere() -> Image:
	var empty_atmosphere = Image.create(1, 1, true, Image.FORMAT_RGBA8)
	empty_atmosphere.set_pixel(0, 0, Color(0, 0, 0, 0))
	return empty_atmosphere

# Main function to create a complete planet texture
func create_planet_texture(seed_value: int, explicit_theme: int = -1) -> Array:
	var theme = explicit_theme if explicit_theme >= 0 else get_planet_theme(seed_value)
	var category = get_planet_category(theme)
	
	# Determine appropriate size based on planet category
	var planet_size = PLANET_SIZE_GASEOUS if category == PlanetCategory.GASEOUS else PLANET_SIZE_TERRAN
	var _planet_radius = PLANET_RADIUS_GASEOUS if category == PlanetCategory.GASEOUS else PLANET_RADIUS_TERRAN
	
	var image = Image.create(planet_size, planet_size, true, Image.FORMAT_RGBA8)
	var colors = generate_planet_palette(theme, seed_value)
	
	var variation_seed_1 = seed_value + 12345
	var variation_seed_2 = seed_value + 67890
	
	var color_size = colors.size() - 1
	var planet_size_minus_one = planet_size - 1
	
	# Main texture generation loop
	for y in range(planet_size):
		var ny = float(y) / planet_size_minus_one
		var dy = ny - 0.5
		
		for x in range(planet_size):
			var nx = float(x) / planet_size_minus_one
			var dx = nx - 0.5
			
			var dist_squared = dx * dx + dy * dy
			var dist = sqrt(dist_squared)
			var normalized_dist = dist * 2.0
			
			# PIXEL-PERFECT EDGE: Use a hard cutoff instead of anti-aliasing
			if normalized_dist >= 1.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			
			# Inside the planet - full alpha
			var alpha = 1.0
			
			var sphere_uv = spherify(nx, ny)
			var color_index = 0
			
			if category == PlanetCategory.GASEOUS:
				# GASEOUS PLANET GENERATION
				# -------------------------
				
				# Generate banding pattern
				var band_value = generate_gas_giant_band(sphere_uv.y, seed_value)
				
				# Add horizontal turbulence
				var turbulence = fbm(sphere_uv.x * 10.0, sphere_uv.y * 2.0, 3, variation_seed_1) * 0.1
				band_value = (band_value + turbulence) * 0.9
				
				# Determine color index - no storms
				color_index = int(band_value * color_size)
				color_index = clamp(color_index, 0, color_size)
				
			else:
				# TERRAN PLANET GENERATION
				# -----------------------
				var base_noise = fbm(sphere_uv.x, sphere_uv.y, TERRAIN_OCTAVES, seed_value)
				var detail_variation_1 = fbm(sphere_uv.x * 3.0, sphere_uv.y * 3.0, 2, variation_seed_1) * 0.1
				var detail_variation_2 = fbm(sphere_uv.x * 5.0, sphere_uv.y * 5.0, 1, variation_seed_2) * 0.05
				
				var combined_noise = base_noise + detail_variation_1 + detail_variation_2
				combined_noise = clamp(combined_noise * COLOR_VARIATION, 0.0, 1.0)
				
				color_index = int(combined_noise * color_size)
				color_index = clamp(color_index, 0, color_size)
			
			var final_color = colors[color_index]
			
			# Create edge shading (darker at edges)
			var edge_shade = 1.0 - pow(normalized_dist, 2) * (0.3 if category == PlanetCategory.GASEOUS else 0.3)
			final_color.r *= edge_shade
			final_color.g *= edge_shade
			final_color.b *= edge_shade
			
			# Apply alpha for pixel-perfect edge
			final_color.a = alpha
			
			image.set_pixel(x, y, final_color)
	
	# Create empty atmosphere placeholder
	var empty_atmosphere = create_empty_atmosphere()
	
	# Return the generated textures
	return [
		ImageTexture.create_from_image(image),
		ImageTexture.create_from_image(empty_atmosphere),
		planet_size
	]
