# scripts/generators/planet_generator.gd
# ==========================
# Purpose:
#   Procedural planet texture generator with support for various planet types
#   Handles generation of both terran and gaseous planets with distinctive themes
#   Creates detailed planet textures with complex noise patterns and features
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
const GAS_GIANT_BAND_NOISE: float = 0.7  # How noisy the bands are
const GAS_GIANT_FLOW: float = 2.5       # How much the bands "flow" horizontally
const GAS_GIANT_STORM_CHANCE: float = 1.0 # Always generate storms (100% chance)
const GAS_GIANT_STORM_MIN_COUNT: int = 2 # Minimum number of storms
const GAS_GIANT_STORM_MAX_COUNT: int = 4 # Maximum number of storms
const GAS_GIANT_STORM_MIN_SIZE: float = 0.03 # Minimum storm size
const GAS_GIANT_STORM_MAX_SIZE: float = 0.12 # Maximum storm size

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

# Create realistic gas giant storms - UPDATED to ensure storm generation
func generate_gas_giant_storms(sphere_uv: Vector2, seed_value: int) -> float:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value + 78912
	
	# Always generate storms - number determined by parameters
	var storm_count = rng.randi_range(GAS_GIANT_STORM_MIN_COUNT, GAS_GIANT_STORM_MAX_COUNT)
	var storm_value = 0.0
	
	# Track storm positions to prevent overlapping
	var storm_positions = []
	
	# Color band for the great red spot - ensure at least one storm is in this band
	var red_spot_band_y = rng.randf_range(0.45, 0.65)
	var red_spot_created = false
	
	for i in range(storm_count):
		# For the first storm, place it in the red spot band
		var storm_y = red_spot_band_y
		var storm_x = rng.randf_range(0.3, 0.7) # Visible part of the planet
		var storm_size = rng.randf_range(GAS_GIANT_STORM_MAX_SIZE * 0.7, GAS_GIANT_STORM_MAX_SIZE) # Larger size for the main spot
		
		# For subsequent storms, use normal distribution
		if i > 0 or red_spot_created:
			storm_y = rng.randf_range(0.3, 0.7)
			storm_x = rng.randf()
			storm_size = rng.randf_range(GAS_GIANT_STORM_MIN_SIZE, GAS_GIANT_STORM_MAX_SIZE)
		else:
			red_spot_created = true
		
		var storm_pos = Vector2(storm_x, storm_y)
		
		# Check for existing storms to avoid overlap
		var too_close = false
		for pos in storm_positions:
			if storm_pos.distance_to(pos.position) < (storm_size + pos.size) * 1.5:
				too_close = true
				break
		
		# Try again if too close to another storm
		if too_close:
			if i > 0: # Don't skip the main red spot
				continue
		
		# Add to tracking array
		storm_positions.append({
			"position": storm_pos,
			"size": storm_size
		})
		
		# Calculate distance to storm center - using adjusted_dist for oval storms
		var adjusted_dist = Vector2(
			(sphere_uv.x - storm_pos.x) * 1.7,  # Oval factor X 
			(sphere_uv.y - storm_pos.y) * 1.0   # Oval factor Y
		).length()
		
		# Add storm if within storm radius
		if adjusted_dist < storm_size:
			# Falloff at edges
			var storm_strength = 1.0 - smoothstep(0, storm_size, adjusted_dist)
			
			# For the first storm (Great Red Spot), always make it darker
			if i == 0 and red_spot_created and adjusted_dist < storm_size * 0.8:
				storm_value -= storm_strength * 0.4
			else:
				# Randomly make storm lighter or darker - with preference for darker
				var storm_polarity = rng.randf() > 0.7
				storm_value += storm_strength * (1.0 if storm_polarity else -1.0) * 0.3
	
	return storm_value

# Generate appropriate color palette for each planet theme
func generate_planet_palette(theme: int, seed_value: int) -> PackedColorArray:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	match theme:
		PlanetTheme.GAS_GIANT:
			# Choose between different gas giant types
			var gas_giant_type = rng.randi() % 4
			
			match gas_giant_type:
				0:  # Jupiter-like (orange/brown tones) - REVISED for more balanced palette
					return PackedColorArray([
						Color(0.88, 0.75, 0.55),  # Muted cream (was too bright)
						Color(0.85, 0.68, 0.42),  # Darker sand
						Color(0.82, 0.58, 0.35),  # Light tan
						Color(0.75, 0.50, 0.25),  # Tan
						Color(0.65, 0.40, 0.20),  # Brown
						Color(0.55, 0.30, 0.15),  # Dark brown
						Color(0.75, 0.35, 0.20),  # Reddish-brown (Great Red Spot)
						Color(0.45, 0.25, 0.15)   # Dark red-brown
					])
				1:  # Saturn-like (yellow/gold tones) - REVISED with less bright colors
					return PackedColorArray([
						Color(0.90, 0.85, 0.68),  # Muted yellow (less bright)
						Color(0.88, 0.83, 0.65),  # Light gold
						Color(0.85, 0.78, 0.58),  # Gold
						Color(0.82, 0.75, 0.50),  # Darker gold
						Color(0.78, 0.68, 0.45),  # Yellow-brown
						Color(0.74, 0.63, 0.40),  # Amber
						Color(0.70, 0.58, 0.35),  # Dark amber
						Color(0.75, 0.45, 0.25)   # Reddish-brown for storms
					])
				2:  # Neptune-like (blue tones) - REVISED with less contrast
					return PackedColorArray([
						Color(0.70, 0.82, 0.90),  # Less bright blue
						Color(0.65, 0.78, 0.88),  # Light blue
						Color(0.58, 0.75, 0.85),  # Sky blue
						Color(0.50, 0.70, 0.82),  # Azure
						Color(0.42, 0.65, 0.78),  # Teal
						Color(0.35, 0.58, 0.75),  # Blue
						Color(0.60, 0.40, 0.25),  # Reddish-brown for storms
						Color(0.25, 0.42, 0.65)   # Navy blue
					])
				3:  # Exotic gas giant - REVISED with more balanced palette
					return PackedColorArray([
						Color(0.90, 0.85, 0.70),  # Toned down pale yellow
						Color(0.87, 0.80, 0.65),  # Light gold
						Color(0.84, 0.75, 0.58),  # Golden
						Color(0.80, 0.70, 0.48),  # Amber
						Color(0.75, 0.62, 0.38),  # Dark amber
						Color(0.70, 0.50, 0.25),  # Brown
						Color(0.68, 0.40, 0.22),  # Reddish-brown (for storms)
						Color(0.78, 0.70, 0.55)   # Beige (less bright)
					])
				_:  # Fallback
					return PackedColorArray([
						Color(0.88, 0.75, 0.55),
						Color(0.82, 0.58, 0.32),
						Color(0.70, 0.42, 0.20),
						Color(0.75, 0.35, 0.18),
						Color(0.45, 0.25, 0.15)
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
func create_planet_texture(seed_value: int) -> Array:
	var theme = get_planet_theme(seed_value)
	var category = get_planet_category(theme)
	
	# Determine appropriate size based on planet category
	var planet_size = PLANET_SIZE_GASEOUS if category == PlanetCategory.GASEOUS else PLANET_SIZE_TERRAN
	var planet_radius = PLANET_RADIUS_GASEOUS if category == PlanetCategory.GASEOUS else PLANET_RADIUS_TERRAN
	
	var image = Image.create(planet_size, planet_size, true, Image.FORMAT_RGBA8)
	var colors = generate_planet_palette(theme, seed_value)
	
	var aa_width = 1.5
	var aa_width_normalized = aa_width / planet_radius
	
	var variation_seed_1 = seed_value + 12345
	var variation_seed_2 = seed_value + 67890
	var storm_seed = seed_value + 13579
	
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
			
			if normalized_dist > 1.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
				
			var alpha = 1.0
			if normalized_dist > (1.0 - aa_width_normalized):
				alpha = 1.0 - (normalized_dist - (1.0 - aa_width_normalized)) / aa_width_normalized
				alpha = clamp(alpha, 0.0, 1.0)
			
			var sphere_uv = spherify(nx, ny)
			var color_index = 0
			
			if category == PlanetCategory.GASEOUS:
				# GASEOUS PLANET GENERATION
				# -------------------------
				
				# Generate banding pattern
				var band_value = generate_gas_giant_band(sphere_uv.y, seed_value)
				
				# Add horizontal turbulence
				var turbulence = fbm(sphere_uv.x * 10.0, sphere_uv.y * 2.0, 3, variation_seed_1) * 0.2
				band_value = (band_value + turbulence) * 0.8
				
				# Get storm influence for this point
				var storm_value = generate_gas_giant_storms(sphere_uv, storm_seed)
				
				# Determine color index for reddish-brown bands
				var band_idx = int(band_value * color_size)
				
				# Find the reddish-brown color index (usually 6, but could vary by palette)
				var red_spot_color_idx = 6  # This is the index with the reddish-brown color
				var is_reddish_band = band_idx == red_spot_color_idx
				
				# Make storm areas use the reddish-brown color
				if storm_value < 0:  # Negative storm values indicate storm areas
					# Force the color to be the reddish-brown for all storms
					band_value = float(red_spot_color_idx) / float(color_size)
				else:
					# Normal band value plus any positive storm effects
					band_value += storm_value
				
				# Get color index based on band value
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
			
			# Apply alpha for anti-aliasing at the edges
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
