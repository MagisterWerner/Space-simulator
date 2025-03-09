# scripts/generators/atmosphere_generator.gd
extends RefCounted
class_name AtmosphereGenerator

# Import the planet theme enums from shared location
const PlanetThemes = preload("res://scripts/generators/planet_themes.gd").PlanetTheme
const PlanetCategories = preload("res://scripts/generators/planet_themes.gd").PlanetCategory

# Gas giant type enum - must match planet_generator_gaseous.gd
enum GasGiantType {
	JUPITER = 0,  # Jupiter-like (beige/tan tones)
	SATURN = 1,   # Saturn-like (golden tones)
	NEPTUNE = 2,  # Neptune-like (blue tones)
	EXOTIC = 3    # Exotic (lavender tones)
}

# Constants for atmosphere generation
const BASE_ATMOSPHERE_SIZE_TERRAN: int = 384
const BASE_ATMOSPHERE_SIZE_GASEOUS: int = 768

# Atmosphere thickness as a percentage beyond planet radius
const ATMOSPHERE_EXTEND_FACTOR_TERRAN: float = 0.30
const ATMOSPHERE_EXTEND_FACTOR_GASEOUS: float = 0.25

# Pixelation settings - different steps for different planet types
const ALPHA_STEPS_TERRAN: int = 16   # 16 steps for normal planets
const ALPHA_STEPS_GASEOUS: int = 32  # 32 steps for gas giants which are twice as large
const MIN_ALPHA_STRENGTH: float = 0.85
const GRADIENT_POWER: float = 1.2

# Edge alignment fix - extend atmosphere slightly under the planet edge
const EDGE_OVERLAP_PIXELS: int = 2  # How many pixels to extend under the planet edge

# Theme-based atmosphere colors for terran planets
const TERRAN_ATMOSPHERE_COLORS = {
	PlanetThemes.ARID: Color(0.8, 0.6, 0.4, 0.35),
	PlanetThemes.ICE: Color(0.8, 0.9, 1.0, 0.3),
	PlanetThemes.LAVA: Color(0.9, 0.3, 0.1, 0.5),
	PlanetThemes.LUSH: Color(0.5, 0.8, 1.0, 0.4),
	PlanetThemes.DESERT: Color(0.9, 0.7, 0.4, 0.45),
	PlanetThemes.ALPINE: Color(0.7, 0.9, 1.0, 0.35),
	PlanetThemes.OCEAN: Color(0.4, 0.7, 0.9, 0.4)
}

# Type-specific atmosphere colors for gas giants
const GASEOUS_ATMOSPHERE_COLORS = {
	GasGiantType.JUPITER: Color(0.75, 0.70, 0.55, 0.45),  # Jupiter-like
	GasGiantType.SATURN: Color(0.80, 0.78, 0.60, 0.4),   # Saturn-like
	GasGiantType.NEPTUNE: Color(0.50, 0.65, 0.75, 0.45), # Neptune-like
	GasGiantType.EXOTIC: Color(0.65, 0.60, 0.75, 0.4)    # Exotic
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
	# Special key for gas giants
	"GAS_GIANT": 1.4
}

# Gas giant type-specific atmosphere thickness
const GASEOUS_ATMOSPHERE_THICKNESS = {
	GasGiantType.JUPITER: 1.4,
	GasGiantType.SATURN: 1.5,
	GasGiantType.NEPTUNE: 1.3,
	GasGiantType.EXOTIC: 1.6
}

# Generate atmosphere data for a TERRAN planet theme
func generate_atmosphere_data(theme: int, seed_value: int) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value + 54321
	
	# Validate theme is a terran type
	if theme == PlanetThemes.GAS_GIANT:
		push_warning("AtmosphereGenerator: Using terran generator for a gas giant theme. Use generate_gas_giant_atmosphere() instead.")
		theme = PlanetThemes.LUSH  # Fallback to a terran theme
	
	# Get base values for this theme
	var base_color = TERRAN_ATMOSPHERE_COLORS.get(theme, Color(0.5, 0.7, 0.9, 0.4))
	var base_thickness = ATMOSPHERE_THICKNESS.get(theme, 1.0)
	
	# Add some variation
	var color_variation = 0.1
	var thickness_variation = 0.2
	
	# Vary the color components slightly
	var r = clamp(base_color.r + (rng.randf() - 0.5) * color_variation, 0, 1)
	var g = clamp(base_color.g + (rng.randf() - 0.5) * color_variation, 0, 1)
	var b = clamp(base_color.b + (rng.randf() - 0.5) * color_variation, 0, 1)
	var a = clamp(base_color.a + (rng.randf() - 0.5) * color_variation * 0.5, 0.15, 0.85)
	
	var color = Color(r, g, b, a)
	var thickness = base_thickness * (1.0 + (rng.randf() - 0.5) * thickness_variation)
	
	# Special adjustments for specific terran planet types
	match theme:
		PlanetThemes.LAVA:
			thickness *= 1.2
			color.a = min(color.a + 0.1, 0.85)
		
		PlanetThemes.OCEAN:
			color.g += 0.05
	
	return {
		"color": color,
		"thickness": thickness,
		"category": PlanetCategories.TERRAN
	}

# NEW METHOD: Generate atmosphere data specifically for a gas giant type
func generate_gas_giant_atmosphere(seed_value: int, giant_type: int) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value + 54321 + giant_type * 1000  # Use type in seed for consistent variation
	
	# Validate giant type
	if giant_type < 0 or giant_type > 3:
		giant_type = 0  # Default to Jupiter-like
	
	# Get base values for this gas giant type
	var base_color = GASEOUS_ATMOSPHERE_COLORS.get(giant_type, Color(0.75, 0.70, 0.55, 0.45))
	var base_thickness = GASEOUS_ATMOSPHERE_THICKNESS.get(giant_type, 1.4)
	
	# Add some variation
	var color_variation = 0.1
	var thickness_variation = 0.15
	
	# Vary the color components slightly
	var r = clamp(base_color.r + (rng.randf() - 0.5) * color_variation, 0, 1)
	var g = clamp(base_color.g + (rng.randf() - 0.5) * color_variation, 0, 1)
	var b = clamp(base_color.b + (rng.randf() - 0.5) * color_variation, 0, 1)
	var a = clamp(base_color.a + (rng.randf() - 0.5) * color_variation * 0.5, 0.25, 0.85)
	
	var color = Color(r, g, b, a)
	var thickness = base_thickness * (1.0 + (rng.randf() - 0.5) * thickness_variation)
	
	# Special adjustments for specific gas giant types
	match giant_type:
		GasGiantType.JUPITER:
			# More pronounced atmosphere
			color.a = min(color.a + 0.05, 0.85)
			
		GasGiantType.NEPTUNE:
			# Bluer atmosphere with slight glow effect
			color.b = min(color.b + 0.05, 1.0)
			
		GasGiantType.EXOTIC:
			# More varied atmospheric effects
			thickness *= 1.1
	
	return {
		"color": color,
		"thickness": thickness,
		"category": PlanetCategories.GASEOUS,
		"giant_type": giant_type
	}

# Generate atmosphere texture for terran planets
func generate_atmosphere_texture(theme: int, seed_value: int, color: Color, thickness_factor: float) -> ImageTexture:
	var is_gaseous = theme == PlanetThemes.GAS_GIANT
	
	# Size will match the actual planet size, not the atmosphere size
	var planet_size = 512 if is_gaseous else 256
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
			
			# Apply special effects for gas giants (subtle bands)
			if is_gaseous and theme == PlanetThemes.GAS_GIANT and alpha > 0.0:
				var y_normalized = float(y) / atmosphere_size
				var band_factor = sin(y_normalized * 8.0 * PI + seed_value) * 0.02
				
				final_color.r = clamp(color.r + band_factor, 0, 1)
				final_color.g = clamp(color.g + band_factor * 0.7, 0, 1)
				final_color.b = clamp(color.b + band_factor * 0.5, 0, 1)
			
			image.set_pixel(x, y, final_color)
	
	# Create texture from image
	return ImageTexture.create_from_image(image)

# NEW METHOD: Generate atmosphere texture for a specific gas giant type
func generate_gas_giant_atmosphere_texture(seed_value: int, giant_type: int) -> ImageTexture:
	# Get the atmosphere data
	var atmosphere_data = generate_gas_giant_atmosphere(seed_value, giant_type)
	var color = atmosphere_data.color
	var thickness = atmosphere_data.thickness
	
	# Size will match the actual planet size, not the atmosphere size
	var planet_size = 512  # Gas giants are always larger
	var planet_radius = planet_size / 2.0
	
	# Calculate the atmosphere size based on the planet size and thickness factor
	var extend_factor = ATMOSPHERE_EXTEND_FACTOR_GASEOUS * thickness
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
	var planet_edge_radius = planet_radius - EDGE_OVERLAP_PIXELS
	var planet_edge_dist = planet_edge_radius / atmosphere_radius
	
	# Determine number of steps for gas giants
	var num_steps = ALPHA_STEPS_GASEOUS
	
	# Precalculate alpha values for each step from edge
	var alpha_steps = []
	for i in range(num_steps):
		var t = float(i) / (num_steps - 1)
		var step_alpha = (1.0 - pow(t, GRADIENT_POWER)) * color.a * MIN_ALPHA_STRENGTH
		alpha_steps.append(step_alpha)
	
	# Prepare RNG for atmosphere noise patterns
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value + 12345 + giant_type * 1000
	
	# Type-specific atmosphere characteristics
	var band_intensity = 0.025  # Base band visual effect intensity
	var band_frequency = 8.0    # Base band frequency
	var color_variation = 0.02  # Base color variation
	
	match giant_type:
		GasGiantType.JUPITER:
			band_frequency = 12.0
			band_intensity = 0.025
			color_variation = 0.02
		GasGiantType.SATURN:
			band_frequency = 10.0
			band_intensity = 0.02
			color_variation = 0.015
		GasGiantType.NEPTUNE:
			band_frequency = 6.0
			band_intensity = 0.03
			color_variation = 0.025
		GasGiantType.EXOTIC:
			band_frequency = 9.0
			band_intensity = 0.035
			color_variation = 0.03
	
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
			
			# Apply gas giant specific band patterns
			if alpha > 0.0:
				var y_normalized = float(y) / atmosphere_size
				
				# Add band patterns - more pronounced for gas giants
				var band_effect = sin(y_normalized * band_frequency * PI + seed_value) * band_intensity
				
				# Add some noise to the bands
				var noise_factor = sin(x * 0.01 + y * 0.02 + seed_value) * color_variation
				
				final_color.r = clamp(color.r + band_effect + noise_factor, 0, 1)
				final_color.g = clamp(color.g + band_effect * 0.7 + noise_factor, 0, 1)
				final_color.b = clamp(color.b + band_effect * 0.5 + noise_factor, 0, 1)
			
			image.set_pixel(x, y, final_color)
	
	# Create texture from image
	return ImageTexture.create_from_image(image)

# Get atmosphere color for a theme (utility function)
func get_atmosphere_color_for_theme(theme: int) -> Color:
	return TERRAN_ATMOSPHERE_COLORS.get(theme, Color(0.5, 0.7, 0.9, 0.4))

# Get atmosphere color for a gas giant type (utility function)
func get_atmosphere_color_for_gas_giant(giant_type: int) -> Color:
	return GASEOUS_ATMOSPHERE_COLORS.get(giant_type, Color(0.75, 0.70, 0.55, 0.45))

# Get atmosphere thickness for a theme (utility function)
func get_atmosphere_thickness_for_theme(theme: int) -> float:
	if theme == PlanetThemes.GAS_GIANT:
		return ATMOSPHERE_THICKNESS.get("GAS_GIANT", 1.0)
	return ATMOSPHERE_THICKNESS.get(theme, 1.0)

# Get atmosphere thickness for a gas giant type (utility function)
func get_atmosphere_thickness_for_gas_giant(giant_type: int) -> float:
	return GASEOUS_ATMOSPHERE_THICKNESS.get(giant_type, 1.4)

# Get base atmosphere size based on planet category
func get_atmosphere_size_for_category(category: int) -> int:
	return BASE_ATMOSPHERE_SIZE_GASEOUS if category == PlanetCategories.GASEOUS else BASE_ATMOSPHERE_SIZE_TERRAN
