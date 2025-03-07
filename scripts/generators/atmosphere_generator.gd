# scripts/generators/atmosphere_generator.gd
extends RefCounted
class_name AtmosphereGenerator

# Import the PlanetGenerator enums directly
const PlanetThemes = preload("res://scripts/generators/planet_generator.gd").PlanetTheme
const PlanetCategories = preload("res://scripts/generators/planet_generator.gd").PlanetCategory

# Constants for atmosphere generation
const BASE_ATMOSPHERE_SIZE_TERRAN: int = 384
const BASE_ATMOSPHERE_SIZE_GASEOUS: int = 768  # Larger atmosphere for gaseous planets
const BASE_THICKNESS_FACTOR_TERRAN: float = 0.3
const BASE_THICKNESS_FACTOR_GASEOUS: float = 0.15  # Thinner relative to size but still substantial

# Theme-based atmosphere colors - using PlanetThemes enum for reference
const ATMOSPHERE_COLORS = {
	PlanetThemes.ARID: Color(0.8, 0.6, 0.4, 0.3),
	PlanetThemes.ICE: Color(0.8, 0.9, 1.0, 0.2),
	PlanetThemes.LAVA: Color(0.9, 0.3, 0.1, 0.5),
	PlanetThemes.LUSH: Color(0.5, 0.8, 1.0, 0.3),
	PlanetThemes.DESERT: Color(0.9, 0.7, 0.4, 0.4),
	PlanetThemes.ALPINE: Color(0.7, 0.9, 1.0, 0.25),
	PlanetThemes.OCEAN: Color(0.4, 0.7, 0.9, 0.35),
	PlanetThemes.GAS_GIANT: Color(0.6, 0.8, 0.9, 0.4)  # Default gas giant atmosphere
}

# Theme-based atmosphere thickness
const ATMOSPHERE_THICKNESS = {
	PlanetThemes.ARID: 1.1,
	PlanetThemes.ICE: 0.8,
	PlanetThemes.LAVA: 1.6,
	PlanetThemes.LUSH: 1.2,
	PlanetThemes.DESERT: 1.3,
	PlanetThemes.ALPINE: 0.9,
	PlanetThemes.OCEAN: 1.15,
	PlanetThemes.GAS_GIANT: 1.4  # Gas giants have substantial atmospheres
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
	
	# Check planet category for specialized processing
	var planet_category = PlanetGenerator.get_planet_category(theme)
	
	# Special handling for gaseous planets (currently only gas giants)
	if planet_category == PlanetCategories.GASEOUS:
		# Different gas giant atmosphere types based on seed
		var gas_giant_type = rng.randi() % 4
		
		match gas_giant_type:
			0:  # Jupiter-like (amber atmosphere)
				base_color = Color(0.9, 0.7, 0.4, 0.45)
			1:  # Saturn-like (pale yellow atmosphere)
				base_color = Color(0.95, 0.9, 0.6, 0.35)
			2:  # Neptune-like (blue atmosphere)
				base_color = Color(0.5, 0.7, 0.9, 0.4)
			3:  # Exotic (unusual coloration)
				base_color = Color(0.8, 0.6, 0.8, 0.4)
		
		# Gaseous planets can have more color variation
		color_variation = 0.15
	
	# Vary the color components slightly
	var r = clamp(base_color.r + (rng.randf() - 0.5) * color_variation, 0, 1)
	var g = clamp(base_color.g + (rng.randf() - 0.5) * color_variation, 0, 1)
	var b = clamp(base_color.b + (rng.randf() - 0.5) * color_variation, 0, 1)
	var a = clamp(base_color.a + (rng.randf() - 0.5) * color_variation * 0.5, 0.05, 0.8)
	
	var color = Color(r, g, b, a)
	var thickness = base_thickness * (1.0 + (rng.randf() - 0.5) * thickness_variation)
	
	# Special adjustments for specific terran planet types
	if planet_category == PlanetCategories.TERRAN:
		match theme:
			PlanetThemes.LAVA:
				thickness *= 1.2
				color.a = min(color.a + 0.1, 0.8)
			
			PlanetThemes.OCEAN:
				color.g += 0.05
	
	# For gaseous planets, ensure appropriate atmospheric characteristics
	if planet_category == PlanetCategories.GASEOUS:
		thickness *= 1.1  # Slightly thicker
		color.a = clamp(color.a + 0.05, 0.3, 0.5)  # More noticeable
	
	return {
		"color": color,
		"thickness": thickness,
		"category": planet_category  # Include the planet category for reference
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
# Parameters theme and seed_value are used to determine category and other properties
func generate_atmosphere_texture(theme: int, seed_value: int, color: Color, thickness_factor: float) -> ImageTexture:
	var planet_category = PlanetGenerator.get_planet_category(theme)
	var is_gaseous = planet_category == PlanetCategories.GASEOUS
	
	var atm_size = BASE_ATMOSPHERE_SIZE_GASEOUS if is_gaseous else BASE_ATMOSPHERE_SIZE_TERRAN
	var image = Image.create(atm_size, atm_size, true, Image.FORMAT_RGBA8)
	
	# CRITICAL: Planet radius must match the planet texture size
	var planet_radius = PlanetGenerator.PLANET_RADIUS_GASEOUS if is_gaseous else PlanetGenerator.PLANET_RADIUS_TERRAN
	
	# Calculate atmosphere dimensions
	# Use exact planet radius as inner radius (no gap) with slight overlap
	var inner_radius = planet_radius - 1.0  # 1px overlap for smoother blend
	var thickness = planet_radius * (BASE_THICKNESS_FACTOR_GASEOUS if is_gaseous else BASE_THICKNESS_FACTOR_TERRAN) * thickness_factor
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
			
			# Special atmosphere effects based on planet category
			var final_color = color
			
			if is_gaseous:
				# Gaseous planets can have slight color variations in their atmosphere
				var angle = atan2(pos.y - center.y, pos.x - center.x)
				var band_factor = sin(angle * 3.0 + seed_value) * 0.05
				
				# Apply subtle color variation
				final_color.r = clamp(color.r + band_factor, 0, 1)
				final_color.g = clamp(color.g + band_factor * 0.7, 0, 1)
				final_color.b = clamp(color.b + band_factor * 0.5, 0, 1)
			
			# Create final pixel color
			var final_alpha = color.a * alpha_curve
			final_color.a = final_alpha
			
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

# Get base atmosphere size based on planet category
func get_atmosphere_size_for_category(category: int) -> int:
	return BASE_ATMOSPHERE_SIZE_GASEOUS if category == PlanetCategories.GASEOUS else BASE_ATMOSPHERE_SIZE_TERRAN
