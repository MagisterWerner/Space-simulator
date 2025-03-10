# scripts/generators/planet_generator_gaseous.gd
# ===========================
# Purpose:
#   Specialized generator for gaseous planet textures
#   Creates detailed gas giant appearances with bands, swirls, and storms
#   Handles different types of gas giants (Jupiter-like, Saturn-like, etc.)
#
# Dependencies:
#   - planet_generator_base.gd
#
extends PlanetGeneratorBase
class_name PlanetGeneratorGaseous

# Gas giant specific constants - Base values for Jupiter/Saturn
const GAS_GIANT_BANDS_BASE: int = 12        # Number of primary bands
const GAS_GIANT_BAND_NOISE_BASE: float = 0.5  # How noisy the bands are
const GAS_GIANT_FLOW_BASE: float = 2.0       # How much the bands "flow" horizontally

# Reduced bands for Uranus/Neptune - more even appearance
const GAS_GIANT_BANDS_CYAN: int = 3          # Fewer bands for ice giants
const GAS_GIANT_BAND_NOISE_CYAN: float = 0.2  # Less noise for smoother appearance
const GAS_GIANT_FLOW_CYAN: float = 0.8        # Less flow for more uniform look

# Get or generate a gaseous planet texture
static func get_gaseous_texture(seed_value: int, theme_id: int = -1) -> Array:
	# Map legacy gas_giant_type (0-3) to the new theme enum values if needed
	if theme_id >= 0 and theme_id <= 3:
		# Convert from the old style (0-3) to the new enum values
		theme_id = PlanetTheme.JUPITER + theme_id
	
	var cache_key = str(seed_value) + "_theme_" + str(theme_id)
	
	if texture_cache.gaseous.has(cache_key):
		return texture_cache.gaseous[cache_key]
	
	var generator = PlanetGeneratorGaseous.new()
	var textures = generator.create_planet_texture(seed_value, theme_id)
	
	texture_cache.gaseous[cache_key] = textures
	clean_texture_cache()
	
	return textures

# Generate appropriate color palette for different gas giant types
func generate_gas_giant_palette(theme_id: int, seed_value: int) -> PackedColorArray:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	match theme_id:
		PlanetTheme.JUPITER:  # Jupiter-like (balanced beige/tan/brown tones)
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
			
		PlanetTheme.SATURN:  # Saturn-like (soft golden/yellow tones)
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
			
		PlanetTheme.URANUS:  # Uranus-like (cyan/teal tones)
			return PackedColorArray([
				Color(0.75, 0.95, 0.95),  # Pale cyan
				Color(0.70, 0.90, 0.90),  # Light cyan
				Color(0.65, 0.85, 0.85),  # Cyan
				Color(0.60, 0.80, 0.80),  # Greenish cyan
				Color(0.55, 0.75, 0.75),  # Teal
				Color(0.50, 0.70, 0.70),  # Medium teal
				Color(0.45, 0.65, 0.65),  # Deep teal
				Color(0.40, 0.60, 0.60)   # Dark teal
			])
			
		PlanetTheme.NEPTUNE:  # Neptune-like (blue tones)
			return PackedColorArray([
				Color(0.40, 0.50, 0.90),  # Bright blue
				Color(0.35, 0.45, 0.85),  # Royal blue
				Color(0.30, 0.40, 0.80),  # Cobalt blue
				Color(0.25, 0.35, 0.75),  # Deep blue
				Color(0.20, 0.30, 0.70),  # Indigo
				Color(0.15, 0.25, 0.65),  # Purple blue
				Color(0.10, 0.20, 0.60),  # Dark indigo
				Color(0.05, 0.15, 0.55)   # Deep indigo
			])
			
		_:  # Fallback to Jupiter if unknown
			return PackedColorArray([
				Color(0.83, 0.78, 0.65),
				Color(0.77, 0.68, 0.55),
				Color(0.71, 0.58, 0.45),
				Color(0.65, 0.48, 0.35),
			])

# Generate gas giant band pattern - Modified to use type-specific parameters
func generate_gas_giant_band(y_coord: float, seed_value: int, theme_id: int) -> float:
	# Select parameters based on giant type
	var band_count: int
	var band_noise: float
	var flow_strength: float
	
	# Use appropriate parameters based on gas giant type
	if theme_id == PlanetTheme.URANUS or theme_id == PlanetTheme.NEPTUNE:
		# Smoother, more even appearance for ice giants
		band_count = GAS_GIANT_BANDS_CYAN
		band_noise = GAS_GIANT_BAND_NOISE_CYAN
		flow_strength = GAS_GIANT_FLOW_CYAN
	else:
		# More bands and detail for gas giants (Jupiter/Saturn)
		band_count = GAS_GIANT_BANDS_BASE
		band_noise = GAS_GIANT_BAND_NOISE_BASE
		flow_strength = GAS_GIANT_FLOW_BASE
	
	# Create primary band structure
	var primary_bands = sin(y_coord * band_count * PI)
	
	# Add noise to make bands irregular
	var noise_seed1 = seed_value + 12345
	var noise_seed2 = seed_value + 54321
	
	var noise_x = y_coord * 5.0
	var noise_y = y_coord * 2.5
	
	var band_noise_value = fbm(noise_x, noise_y, 2, noise_seed1) * band_noise
	
	# Create flow effect (horizontal distortion)
	var flow_x = y_coord * 3.0
	var flow_noise = fbm(flow_x, 0.5, 2, noise_seed2) * flow_strength
	
	return (primary_bands + band_noise_value + flow_noise) * 0.5 + 0.5

# Main texture generation method (override from base class)
func create_planet_texture(seed_value: int, theme_override: int = -1) -> Array:
	# Determine gas giant theme if not explicitly provided
	var theme_id = theme_override
	if theme_id < 0:
		# Extract theme from seed or generate random from the gaseous themes
		var rng = RandomNumberGenerator.new()
		rng.seed = seed_value
		
		# Choose a random gaseous theme (JUPITER to NEPTUNE)
		theme_id = PlanetTheme.JUPITER + rng.randi() % 4
	elif theme_id >= 0 and theme_id <= 3:
		# Support legacy GasGiantType enum (0-3) by mapping to new theme enum values
		theme_id = PlanetTheme.JUPITER + theme_id
	
	# Make sure we have a valid gaseous theme
	if theme_id < PlanetTheme.JUPITER or theme_id > PlanetTheme.NEPTUNE:
		var rng = RandomNumberGenerator.new()
		rng.seed = seed_value
		theme_id = PlanetTheme.JUPITER + rng.randi() % 4
	
	# Set up for gas giant generation
	# Get random planet size based on seed
	var planet_size = get_planet_size(seed_value, true)  # true = gaseous
	var image = Image.create(planet_size, planet_size, true, Image.FORMAT_RGBA8)
	var colors = generate_gas_giant_palette(theme_id, seed_value)
	
	var color_size = colors.size() - 1
	var planet_size_minus_one = planet_size - 1
	
	# Main texture generation loop for gas giant
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
			
			# GASEOUS PLANET GENERATION
			# Generate banding pattern using the revised method that considers planet type
			var band_value = generate_gas_giant_band(sphere_uv.y, seed_value, theme_id)
			
			# Add special gas giant type-specific details
			match theme_id:
				PlanetTheme.JUPITER:
					var spot_x = sphere_uv.x * 8.0
					var spot_y = sphere_uv.y * 4.0 - 0.2
					var spot = fbm(spot_x, spot_y, 2, seed_value + 7890) * 0.1
					if spot > 0.08:
						band_value = max(band_value - 0.1, 0.0)  # Darken spot area
					
				PlanetTheme.SATURN:
					var flow = fbm(sphere_uv.x * 12.0, sphere_uv.y * 8.0, 2, seed_value + 1234) * 0.05
					band_value = band_value * 0.95 + flow
					
				PlanetTheme.NEPTUNE:
					# More even, uniform appearance with subtle swirls
					var smooth_x = sphere_uv.x * 4.0
					var smooth_y = sphere_uv.y * 3.0
					var smooth_color = fbm(smooth_x, smooth_y, 2, seed_value + 4567) * 0.15
					# Blend heavily toward uniform color (less banding)
					band_value = band_value * 0.25 + 0.6 + smooth_color
					
				PlanetTheme.URANUS:
					# More even appearance with subtle variation
					var uniform_x = sphere_uv.x * 3.0
					var uniform_y = sphere_uv.y * 2.0
					var uniform_color = fbm(uniform_x, uniform_y, 2, seed_value + 2468) * 0.1
					# Blend more heavily toward uniform color
					band_value = band_value * 0.3 + 0.5 + uniform_color
			
			# Determine color index based on band value
			var color_index = int(band_value * color_size)
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
	
	# Create empty atmosphere placeholder (atmosphere is handled elsewhere)
	var empty_atmosphere = create_empty_atmosphere()
	
	# Return the generated textures
	return [
		ImageTexture.create_from_image(image),
		ImageTexture.create_from_image(empty_atmosphere),
		planet_size  # Return the actual size used
	]
