extends RefCounted
class_name AtmosphereGenerator

# Import enums directly
const PlanetThemes = preload("res://scripts/generators/planet_generator_base.gd").PlanetTheme
const PlanetCategories = preload("res://scripts/generators/planet_generator_base.gd").PlanetCategory

# Simplified unified constants
const ATMOSPHERE_EXTEND_FACTOR: float = 0.30
const ATMOSPHERE_THICKNESS: float = 0.8
const EDGE_OVERLAP_PIXELS: int = 2
const GRADIENT_POWER: float = 1.2
const MIN_ALPHA_STRENGTH: float = 0.85

# Pixelation settings
const ALPHA_STEPS_TERRAN: int = 16
const ALPHA_STEPS_GASEOUS: int = 32

# Theme-based atmosphere colors using a dictionary
const ATMOSPHERE_COLORS = {
	PlanetThemes.ARID: Color(0.8, 0.6, 0.4, 0.35),
	PlanetThemes.ICE: Color(0.8, 0.9, 1.0, 0.3),
	PlanetThemes.LAVA: Color(0.9, 0.3, 0.1, 0.5),
	PlanetThemes.LUSH: Color(0.5, 0.8, 1.0, 0.4),
	PlanetThemes.DESERT: Color(0.9, 0.7, 0.4, 0.45),
	PlanetThemes.ALPINE: Color(0.7, 0.9, 1.0, 0.35),
	PlanetThemes.OCEAN: Color(0.4, 0.7, 0.9, 0.4),
	PlanetThemes.JUPITER: Color(0.75, 0.70, 0.55, 0.3),
	PlanetThemes.SATURN: Color(0.80, 0.78, 0.60, 0.3),
	PlanetThemes.URANUS: Color(0.65, 0.85, 0.80, 0.3),
	PlanetThemes.NEPTUNE: Color(0.50, 0.65, 0.75, 0.3)
}

# Optimized texture cache with expiration
static var atmosphere_texture_cache: Dictionary = {}
static var cache_age: Dictionary = {}
static var last_cleanup: int = 0

# Generate atmosphere data with specified parameters
func generate_atmosphere_data(theme: int, seed_value: int) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value + 54321
	
	# Get base color and apply variations
	var base_color = ATMOSPHERE_COLORS.get(theme, Color(0.5, 0.7, 0.9, 0.4))
	var color_variation = 0.1
	
	# Apply randomized variations within limits
	var r = clamp(base_color.r + (rng.randf() - 0.5) * color_variation, 0, 1)
	var g = clamp(base_color.g + (rng.randf() - 0.5) * color_variation, 0, 1)
	var b = clamp(base_color.b + (rng.randf() - 0.5) * color_variation, 0, 1)
	var a = clamp(base_color.a + (rng.randf() - 0.5) * color_variation * 0.5, 0.15, 0.85)
	
	var color = Color(r, g, b, a)
	var thickness = ATMOSPHERE_THICKNESS * (1.0 + (rng.randf() - 0.5) * 0.1)
	
	# Adjust for gaseous planets
	var planet_category = PlanetGeneratorBase.get_planet_category(theme)
	if planet_category == PlanetCategories.GASEOUS:
		color.a = clamp(color.a, 0.25, 0.35)
	
	return {
		"color": color,
		"thickness": thickness,
		"category": planet_category
	}

# Clean old textures from cache
static func _clean_texture_cache() -> void:
	var current_time = Time.get_ticks_msec()
	if current_time - last_cleanup < 10000:  # 10 seconds between cleanups
		return
		
	last_cleanup = current_time
	
	var expired_keys = []
	for key in cache_age:
		if current_time - cache_age[key] > 60000:  # 60 seconds expiration
			expired_keys.append(key)
	
	for key in expired_keys:
		atmosphere_texture_cache.erase(key)
		cache_age.erase(key)

# Get cached texture or generate new one
static func get_atmosphere_texture(theme: int, seed_value: int, color: Color, thickness: float, planet_size: int = 0) -> ImageTexture:
	var cache_key = str(theme) + "_" + str(seed_value) + "_" + str(planet_size)
	
	# Process cache cleanup
	_clean_texture_cache()
	
	# Check cache before generating
	if atmosphere_texture_cache.has(cache_key):
		# Update access time
		cache_age[cache_key] = Time.get_ticks_msec()
		return atmosphere_texture_cache[cache_key]
	
	# Generate new texture
	var generator = new()
	var texture = generator.generate_atmosphere_texture(theme, seed_value, color, thickness, planet_size)
	
	# Cache with timestamp
	atmosphere_texture_cache[cache_key] = texture
	cache_age[cache_key] = Time.get_ticks_msec()
	
	return texture

# Main texture generation
func generate_atmosphere_texture(theme: int, seed_value: int, color: Color, thickness_factor: float, planet_size: int = 0) -> ImageTexture:
	var planet_category = PlanetGeneratorBase.get_planet_category(theme)
	var is_gaseous = planet_category == PlanetCategories.GASEOUS
	
	# Calculate sizes
	if planet_size == 0:
		planet_size = PlanetGeneratorBase.get_planet_size(seed_value, is_gaseous)
	
	var planet_radius = planet_size / 2.0
	var atmosphere_radius = planet_radius * (1.0 + ATMOSPHERE_EXTEND_FACTOR * thickness_factor)
	var atmosphere_size = int(atmosphere_radius * 2.0)
	
	# Ensure even size for perfect centering
	if atmosphere_size % 2 != 0:
		atmosphere_size += 1
	
	# Create image
	var image = Image.create(atmosphere_size, atmosphere_size, true, Image.FORMAT_RGBA8)
	
	# Calculate parameters
	var center = Vector2(atmosphere_size / 2.0, atmosphere_size / 2.0)
	var planet_edge_radius = planet_radius - EDGE_OVERLAP_PIXELS
	var planet_edge_dist = planet_edge_radius / atmosphere_radius
	
	# Determine steps based on planet type
	var num_steps = ALPHA_STEPS_GASEOUS if is_gaseous else ALPHA_STEPS_TERRAN
	var steps_scale = clamp(atmosphere_size / (512.0 if is_gaseous else 256.0), 0.5, 2.0)
	num_steps = max(int(num_steps * steps_scale), 8)
	
	# Precalculate alpha steps for performance
	var alpha_steps = []
	for i in range(num_steps):
		var t = float(i) / (num_steps - 1)
		var step_alpha = (1.0 - pow(t, GRADIENT_POWER)) * color.a * MIN_ALPHA_STRENGTH
		alpha_steps.append(step_alpha)
	
	# Generate the atmosphere pixels
	for y in range(atmosphere_size):
		for x in range(atmosphere_size):
			var pos = Vector2(x, y)
			var dist_to_center = pos.distance_to(center)
			
			# Skip pixels outside atmosphere
			if dist_to_center > atmosphere_radius:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			
			# Calculate normalized distance
			var normalized_dist = dist_to_center / atmosphere_radius
			
			# Calculate alpha
			var alpha = 0.0
			
			if normalized_dist > planet_edge_dist:
				# Outside planet edge
				var edge_t = (normalized_dist - planet_edge_dist) / (1.0 - planet_edge_dist)
				edge_t = clamp(edge_t, 0.0, 0.9999)
				var step_index = min(int(floor(edge_t * num_steps)), num_steps - 1)
				alpha = alpha_steps[step_index]
			else:
				# Inside planet edge (overlap)
				alpha = alpha_steps[0]
			
			# Create color with calculated alpha
			var final_color = Color(color.r, color.g, color.b, alpha)
			
			# Apply gas giant effects if needed
			if is_gaseous and alpha > 0.0:
				var y_normalized = float(y) / atmosphere_size
				
				match theme:
					PlanetThemes.JUPITER:
						# Subtle bands
						var band_factor = sin(y_normalized * 8.0 * PI + seed_value) * 0.02
						final_color.r = clamp(color.r + band_factor, 0, 1)
						final_color.g = clamp(color.g + band_factor * 0.7, 0, 1)
						final_color.b = clamp(color.b + band_factor * 0.5, 0, 1)
						
					PlanetThemes.SATURN:
						# Golden bands
						var band_factor = sin(y_normalized * 6.0 * PI + seed_value) * 0.02
						final_color.r = clamp(color.r + band_factor * 1.2, 0, 1)
						final_color.g = clamp(color.g + band_factor * 0.9, 0, 1)
						
					PlanetThemes.URANUS:
						# Subtle variations
						var band_factor = sin(y_normalized * 4.0 * PI + seed_value) * 0.01
						final_color.g = clamp(color.g + band_factor, 0, 1)
						final_color.b = clamp(color.b + band_factor, 0, 1)
						
					PlanetThemes.NEPTUNE:
						# Blue variations
						var band_factor = sin(y_normalized * 5.0 * PI + seed_value) * 0.015
						final_color.b = clamp(color.b + band_factor * 1.2, 0, 1)
			
			image.set_pixel(x, y, final_color)
	
	return ImageTexture.create_from_image(image)

# Utility functions - keep these simple
func get_atmosphere_color_for_theme(theme: int) -> Color:
	return ATMOSPHERE_COLORS.get(theme, Color(0.5, 0.7, 0.9, 0.4))

func get_atmosphere_thickness_for_theme(theme: int) -> float:
	return ATMOSPHERE_THICKNESS
