# scripts/generators/planet_generator_terran.gd
# ============================
# Purpose:
#   Specialized generator for terran-type planets (rocky/terrestrial)
#   Creates detailed planet textures with various climates and features
#   Handles terran planet themes: Arid, Ice, Lava, Lush, Desert, Alpine, Ocean

extends PlanetGeneratorBase
class_name PlanetGeneratorTerran

# Import planet theme enumeration from a shared location
# Using PlanetThemeEnum to avoid conflict with the global PlanetThemes class
const PlanetThemeEnum = preload("res://scripts/generators/planet_themes.gd").PlanetTheme

# Noise generation constants
const TERRAIN_OCTAVES: int = 4
const COLOR_VARIATION: float = 1.5
const PIXEL_RESOLUTION: int = 32

# Theme-based color palettes
var theme_colors = {
	PlanetThemeEnum.ARID: [
		Color(0.90, 0.70, 0.40),
		Color(0.82, 0.58, 0.35),
		Color(0.75, 0.47, 0.30),
		Color(0.70, 0.42, 0.25),
		Color(0.63, 0.38, 0.22),
		Color(0.53, 0.30, 0.16),
		Color(0.40, 0.23, 0.12)
	],
	PlanetThemeEnum.LAVA: [
		Color(1.0, 0.6, 0.0),
		Color(0.9, 0.4, 0.05),
		Color(0.8, 0.2, 0.05),
		Color(0.7, 0.1, 0.05),
		Color(0.55, 0.08, 0.04),
		Color(0.4, 0.06, 0.03),
		Color(0.25, 0.04, 0.02)
	],
	PlanetThemeEnum.LUSH: [
		Color(0.20, 0.70, 0.30),
		Color(0.18, 0.65, 0.25),
		Color(0.15, 0.60, 0.20),
		Color(0.12, 0.55, 0.15),
		Color(0.10, 0.50, 0.10),
		Color(0.35, 0.50, 0.70),
		Color(0.30, 0.45, 0.65),
		Color(0.25, 0.40, 0.60)
	],
	PlanetThemeEnum.ICE: [
		Color(0.98, 0.99, 1.0),
		Color(0.92, 0.97, 1.0),
		Color(0.85, 0.92, 0.98),
		Color(0.75, 0.85, 0.95),
		Color(0.60, 0.75, 0.90),
		Color(0.45, 0.65, 0.85),
		Color(0.30, 0.50, 0.75)
	],
	PlanetThemeEnum.DESERT: [
		Color(0.88, 0.72, 0.45),
		Color(0.85, 0.68, 0.40),
		Color(0.80, 0.65, 0.38),
		Color(0.75, 0.60, 0.35),
		Color(0.70, 0.55, 0.30),
		Color(0.65, 0.50, 0.28),
		Color(0.60, 0.45, 0.25),
		Color(0.48, 0.35, 0.20)
	],
	PlanetThemeEnum.ALPINE: [
		Color(0.98, 0.98, 0.98),
		Color(0.95, 0.95, 0.97),
		Color(0.90, 0.90, 0.95),
		Color(0.85, 0.85, 0.90),
		Color(0.80, 0.85, 0.80),
		Color(0.75, 0.85, 0.75),
		Color(0.70, 0.80, 0.70),
		Color(0.65, 0.75, 0.65)
	],
	PlanetThemeEnum.OCEAN: [
		Color(0.10, 0.35, 0.65),
		Color(0.15, 0.40, 0.70),
		Color(0.15, 0.45, 0.75),
		Color(0.18, 0.50, 0.80),
		Color(0.20, 0.55, 0.85),
		Color(0.25, 0.60, 0.88),
		Color(0.30, 0.65, 0.90),
		Color(0.40, 0.75, 0.95)
	]
}

# Initialize with default values
func _init():
	# Any terran-specific initialization can go here
	pass

# Determine a theme based on seed
# For terran planets, valid themes are 0-6 (all except GAS_GIANT which is 7)
func get_random_theme(seed_value: int) -> int:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng.randi() % PlanetThemeEnum.GAS_GIANT  # 0-6, not including GAS_GIANT

# Main function to generate a terran planet texture
func generate_planet_texture(seed_value: int, theme_id: int = -1) -> Array:
	# If theme_id is negative, generate a random theme based on seed
	if theme_id < 0:
		theme_id = get_random_theme(seed_value)
	
	# Ensure theme is valid for terran planets (not GAS_GIANT)
	if theme_id >= PlanetThemeEnum.GAS_GIANT:
		theme_id = theme_id % PlanetThemeEnum.GAS_GIANT
	
	# Check cache first
	var cache_key = str(seed_value) + "_terran_" + str(theme_id)
	if texture_cache.planets.has(cache_key):
		return [texture_cache.planets[cache_key], null, PLANET_SIZE_TERRAN]
	
	# Create the planet image
	var image = Image.create(PLANET_SIZE_TERRAN, PLANET_SIZE_TERRAN, true, Image.FORMAT_RGBA8)
	
	# Get color palette for this theme
	var colors = theme_colors[theme_id]
	
	# Cache for noise lookup
	var noise_cache = {}
	
	# Generate variation seeds
	var variation_seed_1 = seed_value + 12345
	var variation_seed_2 = seed_value + 67890
	
	# Generation constants
	var color_size = colors.size() - 1
	var planet_size_minus_one = PLANET_SIZE_TERRAN - 1
	
	# Main texture generation loop
	for y in range(PLANET_SIZE_TERRAN):
		var ny = float(y) / planet_size_minus_one
		var dy = ny - 0.5
		
		for x in range(PLANET_SIZE_TERRAN):
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
			
			# TERRAN PLANET GENERATION
			var base_noise = _generate_fbm(sphere_uv.x, sphere_uv.y, TERRAIN_OCTAVES, seed_value, noise_cache)
			var detail_variation_1 = _generate_fbm(sphere_uv.x * 3.0, sphere_uv.y * 3.0, 2, variation_seed_1, noise_cache) * 0.1
			var detail_variation_2 = _generate_fbm(sphere_uv.x * 5.0, sphere_uv.y * 5.0, 1, variation_seed_2, noise_cache) * 0.05
			
			var combined_noise = base_noise + detail_variation_1 + detail_variation_2
			combined_noise = clamp(combined_noise * COLOR_VARIATION, 0.0, 1.0)
			
			var color_index = int(combined_noise * color_size)
			color_index = clamp(color_index, 0, color_size)
			
			var final_color = colors[color_index]
			
			# Create edge shading (darker at edges)
			var edge_shade = 1.0 - pow(normalized_dist, 2) * 0.3
			final_color.r *= edge_shade
			final_color.g *= edge_shade
			final_color.b *= edge_shade
			
			# Apply alpha for pixel-perfect edge
			final_color.a = alpha
			
			image.set_pixel(x, y, final_color)
	
	# Create the texture
	var texture = ImageTexture.create_from_image(image)
	
	# Cache the result
	texture_cache.planets[cache_key] = texture
	cleanup_cache()
	
	# Return the texture array (image, null atmosphere, size)
	return [texture, null, PLANET_SIZE_TERRAN]

# Generate fractal Brownian motion noise for terrain
func _generate_fbm(x: float, y: float, octaves: int, seed_value: int, noise_cache: Dictionary) -> float:
	var value = 0.0
	var amplitude = 0.5
	var frequency = 8.0
	
	for _i in range(octaves):
		value += _generate_noise(x * frequency, y * frequency, seed_value, noise_cache) * amplitude
		frequency *= 2.0
		amplitude *= 0.5
	
	return value

# Generate smooth noise for a point
func _generate_noise(x: float, y: float, seed_value: int, noise_cache: Dictionary) -> float:
	var ix = floor(x)
	var iy = floor(y)
	var fx = x - ix
	var fy = y - iy
	
	# Improved cubic interpolation
	var u = fx * fx * (3.0 - 2.0 * fx)
	var v = fy * fy * (3.0 - 2.0 * fy)
	
	var a = get_random_seed(ix, iy, seed_value, noise_cache)
	var b = get_random_seed(ix + 1.0, iy, seed_value, noise_cache)
	var c = get_random_seed(ix, iy + 1.0, seed_value, noise_cache)
	var d = get_random_seed(ix + 1.0, iy + 1.0, seed_value, noise_cache)
	
	return lerp(
		lerp(a, b, u),
		lerp(c, d, u),
		v
	)

# Generate theme-specific features
func _generate_features(theme_id: int, sphere_uv: Vector2, seed_value: int, noise_cache: Dictionary) -> float:
	match theme_id:
		PlanetThemeEnum.OCEAN:
			# Generate island formations
			return _generate_fbm(sphere_uv.x * 4.0, sphere_uv.y * 4.0, 3, seed_value + 999, noise_cache) * 0.2
			
		PlanetThemeEnum.DESERT, PlanetThemeEnum.ARID:
			# Generate dune patterns
			var dunes = _generate_fbm(sphere_uv.x * 10.0, sphere_uv.y * 5.0, 2, seed_value + 888, noise_cache) * 0.15
			return dunes
			
		PlanetThemeEnum.ICE:
			# Generate crack patterns
			var cracks = _generate_fbm(sphere_uv.x * 15.0, sphere_uv.y * 15.0, 2, seed_value + 777, noise_cache) * 0.1
			return cracks
			
		PlanetThemeEnum.LAVA:
			# Generate lava flow patterns
			var flows = _generate_fbm(sphere_uv.x * 8.0, sphere_uv.y * 8.0, 3, seed_value + 666, noise_cache) * 0.25
			return flows
			
		_:
			return 0.0
