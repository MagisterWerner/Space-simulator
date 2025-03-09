# scripts/generators/atmosphere_generator.gd
extends RefCounted
class_name AtmosphereGenerator

# Import the PlanetGeneratorBase enums directly
const PlanetThemes = preload("res://scripts/generators/planet_generator_base.gd").PlanetTheme
const PlanetCategories = preload("res://scripts/generators/planet_generator_base.gd").PlanetCategory

# Constants for atmosphere generation
const BASE_ATMOSPHERE_SIZE_TERRAN: int = 384
const BASE_ATMOSPHERE_SIZE_GASEOUS: int = 768

# Atmosphere thickness as a percentage beyond planet radius
const ATMOSPHERE_EXTEND_FACTOR_TERRAN: float = 0.30
const ATMOSPHERE_EXTEND_FACTOR_GASEOUS: float = 0.30  # Matched to terran value

# Pixelation settings - different steps for different planet types
const ALPHA_STEPS_TERRAN: int = 16   # 16 steps for normal planets
const ALPHA_STEPS_GASEOUS: int = 32  # 32 steps for gas giants which are twice as large
const MIN_ALPHA_STRENGTH: float = 0.85
const GRADIENT_POWER: float = 1.2

# Edge alignment fix - extend atmosphere slightly under the planet edge
const EDGE_OVERLAP_PIXELS: int = 2  # How many pixels to extend under the planet edge

# Theme-based atmosphere colors - using PlanetThemes enum for reference
const ATMOSPHERE_COLORS = {
	PlanetThemes.ARID: Color(0.8, 0.6, 0.4, 0.35),
	PlanetThemes.ICE: Color(0.8, 0.9, 1.0, 0.3),  
	PlanetThemes.LAVA: Color(0.9, 0.3, 0.1, 0.5),
	PlanetThemes.LUSH: Color(0.5, 0.8, 1.0, 0.4),
	PlanetThemes.DESERT: Color(0.9, 0.7, 0.4, 0.45),
	PlanetThemes.ALPINE: Color(0.7, 0.9, 1.0, 0.35),
	PlanetThemes.OCEAN: Color(0.4, 0.7, 0.9, 0.4),
	# Updated gaseous planet atmosphere colors for each type
	PlanetThemes.JUPITER: Color(0.75, 0.70, 0.55, 0.3),  # Beige/tan atmosphere
	PlanetThemes.SATURN: Color(0.80, 0.78, 0.60, 0.3),   # Golden atmosphere
	PlanetThemes.URANUS: Color(0.65, 0.85, 0.80, 0.3),   # Cyan/teal atmosphere
	PlanetThemes.NEPTUNE: Color(0.50, 0.65, 0.75, 0.3)   # Blue atmosphere
}

# Theme-based atmosphere thickness - CHANGED: All terran planets now use ICE thickness
const ATMOSPHERE_THICKNESS = {
	PlanetThemes.ARID: 0.8,    # Changed to match ICE
	PlanetThemes.ICE: 0.8,     # Thinnest atmosphere - reference value
	PlanetThemes.LAVA: 0.8,    # Changed to match ICE
	PlanetThemes.LUSH: 0.8,    # Changed to match ICE
	PlanetThemes.DESERT: 0.8,  # Changed to match ICE
	PlanetThemes.ALPINE: 0.8,  # Changed to match ICE
	PlanetThemes.OCEAN: 0.8,   # Changed to match ICE
	PlanetThemes.JUPITER: 0.8, # Same thickness for all gaseous planets
	PlanetThemes.SATURN: 0.8,
	PlanetThemes.URANUS: 0.8,
	PlanetThemes.NEPTUNE: 0.8
}

# Texture cache for reuse
static var atmosphere_texture_cache: Dictionary = {}

# Generate atmosphere data for a planet theme
func generate_atmosphere_data(theme: int, seed_value: int) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value + 54321
	
	# Get base values for this theme
	var base_color = ATMOSPHERE_COLORS.get(theme, Color(0.5, 0.7, 0.9, 0.4))
	var base_thickness = ATMOSPHERE_THICKNESS.get(theme, 0.8)  # Default to ICE thickness
	
	# Add some variation
	var color_variation = 0.1
	# CHANGED: Reduced thickness variation to keep atmospheres thin
	var thickness_variation = 0.1  # Reduced from 0.2
	
	# Check planet category for specialized processing
	var planet_category = PlanetGeneratorBase.get_planet_category(theme)
	
	# No need for special handling since all gaseous types now have their own colors
	
	# Vary the color components slightly
	var r = clamp(base_color.r + (rng.randf() - 0.5) * color_variation, 0, 1)
	var g = clamp(base_color.g + (rng.randf() - 0.5) * color_variation, 0, 1)
	var b = clamp(base_color.b + (rng.randf() - 0.5) * color_variation, 0, 1)
	var a = clamp(base_color.a + (rng.randf() - 0.5) * color_variation * 0.5, 0.15, 0.85)
	
	var color = Color(r, g, b, a)
	var thickness = base_thickness * (1.0 + (rng.randf() - 0.5) * thickness_variation)
	
	# For gaseous planets, ensure appropriate atmospheric characteristics
	if planet_category == PlanetCategories.GASEOUS:
		# No additional adjustments needed anymore, already using the ICE thickness
		color.a = clamp(color.a, 0.25, 0.35) # More subtle atmosphere
	
	return {
		"color": color,
		"thickness": thickness,
		"category": planet_category
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

# Generate pixelated atmosphere texture with adaptive step count based on planet type
func generate_atmosphere_texture(theme: int, seed_value: int, color: Color, thickness_factor: float) -> ImageTexture:
	var planet_category = PlanetGeneratorBase.get_planet_category(theme)
	var is_gaseous = planet_category == PlanetCategories.GASEOUS
	
	# Size will match the actual planet size, not the atmosphere size
	var planet_size = PlanetGeneratorBase.PLANET_SIZE_GASEOUS if is_gaseous else PlanetGeneratorBase.PLANET_SIZE_TERRAN
	var planet_radius = planet_size / 2.0
	
	# Calculate the atmosphere size based on the planet size and thickness factor
	var extend_factor = (ATMOSPHERE_EXTEND_FACTOR_GASEOUS if is_gaseous else ATMOSPHERE_EXTEND_FACTOR_TERRAN) * thickness_factor
	var atmosphere_radius = planet_radius * (1.0 + extend_factor)
	var atmosphere_size = int(atmosphere_radius * 2.0)
	
	# Ensure atmosphere size is even for perfect centering
	if atmosphere_size % 2 != 0:
		atmosphere_size += 1
	
	# Create the atmosphere image
	var image = Image.create(atmosphere_size, atmosphere_size, true, Image.FORMAT_RGBA8)
	
	# Calculate center of the image
	var center = Vector2(atmosphere_size / 2.0, atmosphere_size / 2.0)
	
	# Calculate modified planet edge distance that extends slightly underneath the planet
	# This fixes the edge gap by ensuring atmosphere color extends under the planet edge
	var planet_edge_radius = planet_radius - EDGE_OVERLAP_PIXELS
	var planet_edge_dist = planet_edge_radius / atmosphere_radius
	
	# Determine number of steps based on planet category
	var num_steps = ALPHA_STEPS_GASEOUS if is_gaseous else ALPHA_STEPS_TERRAN
	
	# Precalculate alpha values for each step from edge
	var alpha_steps = []
	for i in range(num_steps):
		var t = float(i) / (num_steps - 1)
		var step_alpha = (1.0 - pow(t, GRADIENT_POWER)) * color.a * MIN_ALPHA_STRENGTH
		alpha_steps.append(step_alpha)
	
	# Draw the atmosphere
	for y in range(atmosphere_size):
		for x in range(atmosphere_size):
			var pos = Vector2(x, y)
			var dist_to_center = pos.distance_to(center)
			
			# Skip pixels outside the atmosphere radius
			if dist_to_center > atmosphere_radius:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			
			# Calculate normalized distance (0 at center, 1 at edge)
			var normalized_dist = dist_to_center / atmosphere_radius
			
			# Calculate alpha based on distance from modified planet edge to atmosphere edge
			var alpha = 0.0
			
			if normalized_dist > planet_edge_dist:
				# Calculate how far we are from planet edge to atmosphere edge (0 to 1)
				var edge_t = (normalized_dist - planet_edge_dist) / (1.0 - planet_edge_dist)
				
				# Ensure edge_t is within 0-1 range to prevent array out of bounds
				edge_t = clamp(edge_t, 0.0, 0.9999)
				
				# Determine which step this pixel belongs to
				var step_index = int(floor(edge_t * num_steps))
				
				# Safety check for index bounds
				if step_index >= num_steps:
					step_index = num_steps - 1
				
				alpha = alpha_steps[step_index]
			else:
				# Inside the modified planet edge - these pixels will be under the planet
				# Set a constant alpha for the edge extension to ensure smooth transition
				alpha = alpha_steps[0]  # Use highest alpha value
			
			# Create the final color with calculated alpha
			var final_color = Color(color.r, color.g, color.b, alpha)
			
			# Apply special effects for gas giants based on type
			if is_gaseous and alpha > 0.0:
				var y_normalized = float(y) / atmosphere_size
				
				match theme:
					PlanetThemes.JUPITER:
						# Subtle tan bands
						var band_factor = sin(y_normalized * 8.0 * PI + seed_value) * 0.02
						final_color.r = clamp(color.r + band_factor, 0, 1)
						final_color.g = clamp(color.g + band_factor * 0.7, 0, 1)
						final_color.b = clamp(color.b + band_factor * 0.5, 0, 1)
						
					PlanetThemes.SATURN:
						# Golden bands with more orange
						var band_factor = sin(y_normalized * 6.0 * PI + seed_value) * 0.02
						final_color.r = clamp(color.r + band_factor * 1.2, 0, 1)
						final_color.g = clamp(color.g + band_factor * 0.9, 0, 1)
						
					PlanetThemes.URANUS:
						# Subtle cyan variations
						var band_factor = sin(y_normalized * 4.0 * PI + seed_value) * 0.01
						final_color.g = clamp(color.g + band_factor, 0, 1)
						final_color.b = clamp(color.b + band_factor, 0, 1)
						
					PlanetThemes.NEPTUNE:
						# Blue variations
						var band_factor = sin(y_normalized * 5.0 * PI + seed_value) * 0.015
						final_color.b = clamp(color.b + band_factor * 1.2, 0, 1)
			
			image.set_pixel(x, y, final_color)
	
	# Create texture from image
	return ImageTexture.create_from_image(image)

# Get atmosphere color for a theme (utility function)
func get_atmosphere_color_for_theme(theme: int) -> Color:
	return ATMOSPHERE_COLORS.get(theme, Color(0.5, 0.7, 0.9, 0.4))

# Get atmosphere thickness for a theme (utility function)
func get_atmosphere_thickness_for_theme(theme: int) -> float:
	return ATMOSPHERE_THICKNESS.get(theme, 0.8)  # Default to ICE thickness

# Get base atmosphere size based on planet category
func get_atmosphere_size_for_category(category: int) -> int:
	return BASE_ATMOSPHERE_SIZE_GASEOUS if category == PlanetCategories.GASEOUS else BASE_ATMOSPHERE_SIZE_TERRAN
