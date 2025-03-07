# scripts/generators/atmosphere_generator.gd
# Fixed atmosphere generator with perfect planet edge alignment
extends RefCounted
class_name AtmosphereGenerator

enum PlanetTheme {
	ARID,
	ICE,
	LAVA,
	LUSH,
	DESERT,
	ALPINE,
	OCEAN
}

# Constants for atmosphere generation
const BASE_ATMOSPHERE_SIZE: int = 384
const BASE_THICKNESS_FACTOR: float = 0.3

# Theme-based atmosphere colors
const ATMOSPHERE_COLORS = {
	PlanetTheme.ARID: Color(0.8, 0.6, 0.4, 0.3),
	PlanetTheme.ICE: Color(0.8, 0.9, 1.0, 0.2),
	PlanetTheme.LAVA: Color(0.9, 0.3, 0.1, 0.5),
	PlanetTheme.LUSH: Color(0.5, 0.8, 1.0, 0.3),
	PlanetTheme.DESERT: Color(0.9, 0.7, 0.4, 0.4),
	PlanetTheme.ALPINE: Color(0.7, 0.9, 1.0, 0.25),
	PlanetTheme.OCEAN: Color(0.4, 0.7, 0.9, 0.35)
}

# Theme-based atmosphere thickness
const ATMOSPHERE_THICKNESS = {
	PlanetTheme.ARID: 1.1,
	PlanetTheme.ICE: 0.8,
	PlanetTheme.LAVA: 1.6,
	PlanetTheme.LUSH: 1.2,
	PlanetTheme.DESERT: 1.3,
	PlanetTheme.ALPINE: 0.9,
	PlanetTheme.OCEAN: 1.15
}

# Texture cache for reuse
static var atmosphere_texture_cache: Dictionary = {}

# Generate atmosphere data for a planet theme
func generate_atmosphere_data(theme: int, seed_value: int) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value + 54321
	
	# Get base values for this theme
	var base_color = ATMOSPHERE_COLORS.get(theme, Color(0.5, 0.7, 0.9, 0.3))
	var base_thickness = ATMOSPHERE_THICKNESS.get(theme, 1.0)
	
	# Add some variation
	var color_variation = 0.1
	var thickness_variation = 0.2
	
	# Vary the color components slightly
	var r = clamp(base_color.r + (rng.randf() - 0.5) * color_variation, 0, 1)
	var g = clamp(base_color.g + (rng.randf() - 0.5) * color_variation, 0, 1)
	var b = clamp(base_color.b + (rng.randf() - 0.5) * color_variation, 0, 1)
	var a = clamp(base_color.a + (rng.randf() - 0.5) * color_variation * 0.5, 0.05, 0.8)
	
	var color = Color(r, g, b, a)
	var thickness = base_thickness * (1.0 + (rng.randf() - 0.5) * thickness_variation)
	
	# Special adjustments for certain planet types
	if theme == PlanetTheme.LAVA:
		thickness *= 1.2
		color.a = min(color.a + 0.1, 0.8)
	
	if theme == PlanetTheme.OCEAN:
		color.g += 0.05
	
	return {
		"color": color,
		"thickness": thickness
	}

# Static function to get an atmosphere texture with caching
static func get_atmosphere_texture(theme: int, seed_value: int, color: Color, thickness: float) -> ImageTexture:
	var cache_key = str(theme) + "_" + str(seed_value)
	
	# Check if we have this texture in cache
	if atmosphere_texture_cache.has(cache_key):
		return atmosphere_texture_cache[cache_key]
	
	# Create a new generator and generate the texture
	var generator = new()
	var texture = generator.generate_atmosphere_texture(theme, seed_value, color, thickness)
	
	# Store in cache
	atmosphere_texture_cache[cache_key] = texture
	
	# Limit cache size
	if atmosphere_texture_cache.size() > 50:
		var oldest_key = atmosphere_texture_cache.keys()[0]
		atmosphere_texture_cache.erase(oldest_key)
	
	return texture

# Generate atmosphere texture with perfect planet edge alignment
# Parameters _theme and _seed_value are kept for API compatibility but not used directly
func generate_atmosphere_texture(_theme: int, _seed_value: int, color: Color, thickness_factor: float) -> ImageTexture:
	var atm_size = BASE_ATMOSPHERE_SIZE
	var image = Image.create(atm_size, atm_size, true, Image.FORMAT_RGBA8)
	
	# CRITICAL: Planet radius must be exactly 127 to match 256px planet textures
	var planet_radius = 127.0
	
	# Calculate atmosphere dimensions
	# Use exact planet radius as inner radius (no gap) with slight overlap
	var inner_radius = planet_radius - 1.0  # 1px overlap for smoother blend
	var thickness = planet_radius * BASE_THICKNESS_FACTOR * thickness_factor
	var outer_radius = planet_radius + thickness
	
	# Center of the texture
	var center = Vector2(atm_size / 2.0, atm_size / 2.0)
	
	# Generate the atmosphere
	for y in range(atm_size):
		for x in range(atm_size):
			var pos = Vector2(x, y)
			var dist = pos.distance_to(center)
			
			# Skip pixels way outside the outer radius
			if dist > outer_radius:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			
			# Inside the planet (but leave the slight overlap)
			if dist < inner_radius - 1.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			
			# Special handling for the overlap area
			if dist < planet_radius:
				# 1px feathered edge within planet boundary
				var fade_in = (dist - (inner_radius - 1.0)) / 2.0
				fade_in = clamp(fade_in, 0.0, 1.0)
				var overlap_alpha = color.a * 0.4 * fade_in  # Subtle effect
				image.set_pixel(x, y, Color(color.r, color.g, color.b, overlap_alpha))
				continue
			
			# For the actual atmosphere glow
			var atmosphere_t = (dist - planet_radius) / thickness
			if atmosphere_t > 1.0:
				atmosphere_t = 1.0
				
			# Alpha fades from full at planet edge to zero at outer edge
			var alpha_curve = 1.0 - atmosphere_t
			
			# Use cubic curve for smoother gradient
			alpha_curve = alpha_curve * alpha_curve * (3.0 - 2.0 * alpha_curve)
			
			# Create final pixel color
			var final_alpha = color.a * alpha_curve
			var final_color = Color(color.r, color.g, color.b, final_alpha)
			
			# Apply the pixel
			image.set_pixel(x, y, final_color)
	
	# Create texture from image
	return ImageTexture.create_from_image(image)

# Get atmosphere color for a theme (utility function)
func get_atmosphere_color_for_theme(theme: int) -> Color:
	return ATMOSPHERE_COLORS.get(theme, Color(0.5, 0.7, 0.9, 0.3))

# Get atmosphere thickness for a theme (utility function)
func get_atmosphere_thickness_for_theme(theme: int) -> float:
	return ATMOSPHERE_THICKNESS.get(theme, 1.0)
