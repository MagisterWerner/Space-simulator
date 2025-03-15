extends PlanetGeneratorBase
class_name PlanetGeneratorGaseous

# Gas giant specific constants
const GAS_GIANT_BANDS_BASE: int = 12
const GAS_GIANT_BAND_NOISE_BASE: float = 0.5
const GAS_GIANT_FLOW_BASE: float = 2.0

# Reduced bands for ice giants
const GAS_GIANT_BANDS_CYAN: int = 3
const GAS_GIANT_BAND_NOISE_CYAN: float = 0.2
const GAS_GIANT_FLOW_CYAN: float = 0.8

# Get or generate a gaseous planet texture
static func get_gaseous_texture(seed_value: int, theme_id: int = -1) -> Array:
	# Convert legacy type if needed
	if theme_id >= 0 and theme_id <= 3:
		theme_id = PlanetTheme.JUPITER + theme_id
	
	var cache_key = str(seed_value) + "_theme_" + str(theme_id)
	var current_time = Time.get_ticks_msec()
	
	# Check cache
	if texture_cache.gaseous.has(cache_key):
		if cache_timestamps.has("gaseous"):
			cache_timestamps.gaseous[cache_key] = current_time
		return texture_cache.gaseous[cache_key]
	
	# Generate new texture
	var generator = PlanetGeneratorGaseous.new()
	var textures = generator.create_planet_texture(seed_value, theme_id)
	
	# Cache with timestamp
	texture_cache.gaseous[cache_key] = textures
	if not cache_timestamps.has("gaseous"):
		cache_timestamps.gaseous = {}
	cache_timestamps.gaseous[cache_key] = current_time
	
	clean_texture_cache()
	
	return textures

# Generate color palette for gas giant type
func generate_gas_giant_palette(theme_id: int, seed_value: int) -> PackedColorArray:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	match theme_id:
		PlanetTheme.JUPITER:  # Jupiter-like
			return PackedColorArray([
				Color(0.83, 0.78, 0.65),
				Color(0.77, 0.68, 0.55),
				Color(0.71, 0.58, 0.45),
				Color(0.65, 0.48, 0.35),
				Color(0.62, 0.43, 0.30)
			])
			
		PlanetTheme.SATURN:  # Saturn-like
			return PackedColorArray([
				Color(0.85, 0.82, 0.70),
				Color(0.81, 0.78, 0.62),
				Color(0.77, 0.74, 0.54),
				Color(0.73, 0.70, 0.46),
				Color(0.71, 0.68, 0.42)
			])
			
		PlanetTheme.URANUS:  # Uranus-like
			return PackedColorArray([
				Color(0.75, 0.95, 0.95),
				Color(0.65, 0.85, 0.85),
				Color(0.55, 0.75, 0.75),
				Color(0.45, 0.65, 0.65),
				Color(0.40, 0.60, 0.60)
			])
			
		PlanetTheme.NEPTUNE:  # Neptune-like
			return PackedColorArray([
				Color(0.40, 0.50, 0.90),
				Color(0.30, 0.40, 0.80),
				Color(0.20, 0.30, 0.70),
				Color(0.10, 0.20, 0.60),
				Color(0.05, 0.15, 0.55)
			])
			
		_:  # Fallback to Jupiter
			return PackedColorArray([
				Color(0.83, 0.78, 0.65),
				Color(0.77, 0.68, 0.55),
				Color(0.71, 0.58, 0.45),
				Color(0.65, 0.48, 0.35)
			])

# Generate band pattern for gas giant
func generate_gas_giant_band(y_coord: float, seed_value: int, theme_id: int) -> float:
	# Select parameters based on type
	var band_count: int
	var band_noise: float
	var flow_strength: float
	
	# Configure based on gas giant type
	if theme_id == PlanetTheme.URANUS or theme_id == PlanetTheme.NEPTUNE:
		band_count = GAS_GIANT_BANDS_CYAN
		band_noise = GAS_GIANT_BAND_NOISE_CYAN
		flow_strength = GAS_GIANT_FLOW_CYAN
	else:
		band_count = GAS_GIANT_BANDS_BASE
		band_noise = GAS_GIANT_BAND_NOISE_BASE
		flow_strength = GAS_GIANT_FLOW_BASE
	
	# Create primary band structure
	var primary_bands = sin(y_coord * band_count * PI)
	
	# Add noise for irregularity
	var noise_seed1 = seed_value + 12345
	var noise_seed2 = seed_value + 54321
	
	var noise_x = y_coord * 5.0
	var noise_y = y_coord * 2.5
	
	var band_noise_value = fbm(noise_x, noise_y, 2, noise_seed1) * band_noise
	
	# Create flow effect (horizontal distortion)
	var flow_x = y_coord * 3.0
	var flow_noise = fbm(flow_x, 0.5, 2, noise_seed2) * flow_strength
	
	return (primary_bands + band_noise_value + flow_noise) * 0.5 + 0.5

# Main texture generation method
func create_planet_texture(seed_value: int, theme_override: int = -1) -> Array:
	# Determine gas giant theme
	var theme_id = theme_override
	if theme_id < 0:
		var rng = RandomNumberGenerator.new()
		rng.seed = seed_value
		theme_id = PlanetTheme.JUPITER + rng.randi() % 4
	elif theme_id >= 0 and theme_id <= 3:
		theme_id = PlanetTheme.JUPITER + theme_id
	
	# Validate theme
	if theme_id < PlanetTheme.JUPITER or theme_id > PlanetTheme.NEPTUNE:
		var rng = RandomNumberGenerator.new()
		rng.seed = seed_value
		theme_id = PlanetTheme.JUPITER + rng.randi() % 4
	
	# Set up generation parameters
	var planet_size = get_planet_size(seed_value, true)
	var image = Image.create(planet_size, planet_size, true, Image.FORMAT_RGBA8)
	var colors = generate_gas_giant_palette(theme_id, seed_value)
	
	var color_size = colors.size() - 1
	var planet_size_minus_one = planet_size - 1
	
	# Precompute normalized coordinates
	var nx_lookup: PackedFloat32Array = PackedFloat32Array()
	var ny_lookup: PackedFloat32Array = PackedFloat32Array()
	nx_lookup.resize(planet_size)
	ny_lookup.resize(planet_size)
	
	for i in range(planet_size):
		nx_lookup[i] = float(i) / planet_size_minus_one
		ny_lookup[i] = float(i) / planet_size_minus_one
	
	# Main generation loop
	for y in range(planet_size):
		var ny = ny_lookup[y]
		var dy = ny - 0.5
		
		for x in range(planet_size):
			var nx = nx_lookup[x]
			var dx = nx - 0.5
			
			var dist_squared = dx * dx + dy * dy
			var dist = sqrt(dist_squared)
			var normalized_dist = dist * 2.0
			
			# Skip pixels outside the planet
			if normalized_dist >= 1.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			
			# Inside the planet - full alpha
			var sphere_uv = spherify(nx, ny)
			
			# Generate banding pattern
			var band_value = generate_gas_giant_band(sphere_uv.y, seed_value, theme_id)
			
			# Apply special effects based on type
			match theme_id:
				PlanetTheme.JUPITER:
					# Great spot effect
					var spot_x = sphere_uv.x * 8.0
					var spot_y = sphere_uv.y * 4.0 - 0.2
					var spot = fbm(spot_x, spot_y, 2, seed_value + 7890) * 0.1
					if spot > 0.08:
						band_value = max(band_value - 0.1, 0.0)
						
				PlanetTheme.SATURN:
					# Flowing bands
					var flow = fbm(sphere_uv.x * 12.0, sphere_uv.y * 8.0, 2, seed_value + 1234) * 0.05
					band_value = band_value * 0.95 + flow
					
				PlanetTheme.NEPTUNE:
					# More uniform with swirls
					var smooth_x = sphere_uv.x * 4.0
					var smooth_y = sphere_uv.y * 3.0
					var smooth_color = fbm(smooth_x, smooth_y, 2, seed_value + 4567) * 0.15
					band_value = band_value * 0.25 + 0.6 + smooth_color
					
				PlanetTheme.URANUS:
					# Even appearance
					var uniform_x = sphere_uv.x * 3.0
					var uniform_y = sphere_uv.y * 2.0
					var uniform_color = fbm(uniform_x, uniform_y, 2, seed_value + 2468) * 0.1
					band_value = band_value * 0.3 + 0.5 + uniform_color
			
			# Get color from palette
			var color_index = int(band_value * color_size)
			color_index = clamp(color_index, 0, color_size)
			
			var final_color = colors[color_index]
			
			# Edge shading
			var edge_shade = 1.0 - pow(normalized_dist, 2) * 0.3
			final_color.r *= edge_shade
			final_color.g *= edge_shade
			final_color.b *= edge_shade
			final_color.a = 1.0
			
			image.set_pixel(x, y, final_color)
	
	# Create empty atmosphere placeholder
	var empty_atmosphere = create_empty_atmosphere()
	
	# Return results
	return [
		ImageTexture.create_from_image(image),
		ImageTexture.create_from_image(empty_atmosphere),
		planet_size
	]
