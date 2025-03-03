# atmosphere_generator.gd - Procedural atmosphere generation system
extends RefCounted

# Planet theme enum (copied from planet_generator.gd for reference)
enum PlanetTheme {
	ARID,       # Desert-like, sandy colors
	ICE,        # Cold, bluish-white palette
	LAVA,       # Volcanic, red and orange hues
	LUSH,       # Green and blue, vegetation-like
	DESERT,     # Dry, sandy, with rock formations
	ALPINE,     # Mountain and snow-capped terrain with forests
	OCEAN       # Predominantly water-based world
}

# Atmosphere parameters
const BASE_ATMOSPHERE_SIZE: int = 384  # Increased to ensure no clipping at edges
const INNER_RADIUS_FACTOR: float = 0.97  # Where the atmosphere starts (relative to planet edge)
const BASE_THICKNESS_FACTOR: float = 0.26  # Base thickness of the atmosphere (0-1)

# Atmosphere color by planet type
const ATMOSPHERE_COLORS = {
	PlanetTheme.ARID: Color(0.8, 0.6, 0.4, 0.3),      # Dusty brownish
	PlanetTheme.ICE: Color(0.8, 0.9, 1.0, 0.2),       # Pale blue-white
	PlanetTheme.LAVA: Color(0.9, 0.3, 0.1, 0.5),      # Reddish with more opacity
	PlanetTheme.LUSH: Color(0.5, 0.8, 1.0, 0.3),      # Light blue (oxygen-rich)
	PlanetTheme.DESERT: Color(0.9, 0.7, 0.4, 0.4),    # Sandy brown with haze
	PlanetTheme.ALPINE: Color(0.7, 0.9, 1.0, 0.25),   # Clear light blue
	PlanetTheme.OCEAN: Color(0.4, 0.7, 0.9, 0.35)     # Deep blue with more moisture
}

# Atmosphere thickness by planet type (multiplier for base thickness)
const ATMOSPHERE_THICKNESS = {
	PlanetTheme.ARID: 1.1,       # Slightly thicker
	PlanetTheme.ICE: 0.8,        # Thinner
	PlanetTheme.LAVA: 1.6,       # Much thicker
	PlanetTheme.LUSH: 1.2,       # Thicker
	PlanetTheme.DESERT: 1.3,     # Thicker
	PlanetTheme.ALPINE: 0.9,     # Slightly thinner
	PlanetTheme.OCEAN: 1.15      # Slightly thicker
}

# Cache for generated atmospheres by seed
static var atmosphere_texture_cache: Dictionary = {}

# Generate atmosphere data based on planet theme and seed
func generate_atmosphere_data(theme: int, seed_value: int) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value + 54321  # Use different offset for atmosphere seed
	
	# Get base color and thickness for this theme
	var base_color = ATMOSPHERE_COLORS.get(theme, Color(0.5, 0.7, 0.9, 0.3))  # Default to light blue
	var base_thickness = ATMOSPHERE_THICKNESS.get(theme, 1.0)  # Default to normal thickness
	
	# Add small random variations to color and thickness
	var color_variation = 0.1
	var thickness_variation = 0.2
	
	var r = clamp(base_color.r + (rng.randf() - 0.5) * color_variation, 0, 1)
	var g = clamp(base_color.g + (rng.randf() - 0.5) * color_variation, 0, 1)
	var b = clamp(base_color.b + (rng.randf() - 0.5) * color_variation, 0, 1)
	var a = clamp(base_color.a + (rng.randf() - 0.5) * color_variation * 0.5, 0.05, 0.8)
	
	var color = Color(r, g, b, a)
	var thickness = base_thickness * (1.0 + (rng.randf() - 0.5) * thickness_variation)
	
	# For lava planets, add increased thickness and opacity
	if theme == PlanetTheme.LAVA:
		thickness *= 1.2
		color.a = min(color.a + 0.1, 0.8)
	
	# For ocean planets, add slight blue-green tint
	if theme == PlanetTheme.OCEAN:
		color.g += 0.05
	
	return {
		"color": color,
		"thickness": thickness
	}

# Get a cached atmosphere texture or generate a new one
static func get_atmosphere_texture(theme: int, seed_value: int, color: Color, thickness: float) -> ImageTexture:
	var cache_key = str(theme) + "_" + str(seed_value)
	
	if atmosphere_texture_cache.has(cache_key):
		return atmosphere_texture_cache[cache_key]
	
	var generator = new()
	var texture = generator.generate_atmosphere_texture(theme, seed_value, color, thickness)
	
	# Cache the texture
	atmosphere_texture_cache[cache_key] = texture
	
	# Limit cache size to prevent memory issues
	if atmosphere_texture_cache.size() > 50:
		var oldest_key = atmosphere_texture_cache.keys()[0]
		atmosphere_texture_cache.erase(oldest_key)
	
	return texture

# Generate atmosphere texture with improved quality
func generate_atmosphere_texture(theme: int, seed_value: int, color: Color, thickness_factor: float) -> ImageTexture:
	# Create image with proper size - larger to ensure no clipping
	var atm_size = BASE_ATMOSPHERE_SIZE
	var image = Image.create(atm_size, atm_size, true, Image.FORMAT_RGBA8)
	
	# Calculate atmosphere parameters
	var planet_radius = 127.0  # Half of planet size (256/2) with slight adjustment for perfect centering
	var inner_radius = planet_radius * INNER_RADIUS_FACTOR  # Start slightly inside planet edge
	var thickness = planet_radius * BASE_THICKNESS_FACTOR * thickness_factor
	var outer_radius = planet_radius + thickness
	
	# Center of the atmosphere
	var center = Vector2(atm_size / 2.0, atm_size / 2.0)
	
	# Additional atmosphere variations based on theme
	var noise_scale = 0.0
	var noise_amount = 0.0
	var cloud_bands = false
	var dust_streaks = false
	
	# Set special atmosphere effects based on planet type
	match theme:
		PlanetTheme.LAVA:
			noise_scale = 8.0
			noise_amount = 0.3
			cloud_bands = false
		PlanetTheme.ARID, PlanetTheme.DESERT:
			noise_scale = 6.0
			noise_amount = 0.2
			dust_streaks = true
		PlanetTheme.OCEAN, PlanetTheme.LUSH:
			noise_scale = 4.0
			noise_amount = 0.15
			cloud_bands = true
	
	# Create RNG for noise generation
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value + 54321  # Different offset for atmosphere
	
	# Generate the atmosphere with radial gradient
	for y in range(atm_size):
		for x in range(atm_size):
			var pos = Vector2(x, y)
			var dist = pos.distance_to(center)
			
			# Skip pixels outside the outer radius and inside the inner radius
			if dist > outer_radius or dist < inner_radius:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			
			# Calculate base alpha based on distance (stronger near planet, fading outward)
			var atmosphere_t = (dist - inner_radius) / (outer_radius - inner_radius)
			
			# Enhanced smooth curve for alpha falloff
			var alpha_curve = 1.0 - atmosphere_t  # Linear falloff base
			alpha_curve = alpha_curve * alpha_curve * (3.0 - 2.0 * alpha_curve)  # Smooth step
			
			# Apply noise if enabled
			var noise_factor = 1.0
			if noise_amount > 0:
				var angle = atan2(y - center.y, x - center.x)
				var noise_value = 0.0
				
				if cloud_bands:
					# Horizontal cloud bands
					noise_value = sin(angle * 2.0 + rng.randf() * TAU)
					noise_value = noise_value * 0.5 + 0.5  # Normalize to 0-1
				elif dust_streaks:
					# Dust streaks
					noise_value = sin(angle * 3.0 + cos(angle * 2.0) + rng.randf() * TAU)
					noise_value = noise_value * 0.5 + 0.5  # Normalize to 0-1
				else:
					# General noise
					noise_value = sin(angle * rng.randf_range(2.0, 4.0) + rng.randf() * TAU)
					noise_value = noise_value * 0.5 + 0.5  # Normalize to 0-1
				
				noise_factor = 1.0 - noise_amount + noise_value * noise_amount
			
			# Apply the alpha curve and noise factor
			var final_alpha = color.a * alpha_curve * noise_factor
			
			# Ensure smooth fading at outer edges
			if atmosphere_t > 0.85:
				final_alpha *= (1.0 - (atmosphere_t - 0.85) / 0.15)
			
			# Create the final color - ensure atmosphere gets more transparent at edges
			var final_color = Color(color.r, color.g, color.b, final_alpha)
			
			image.set_pixel(x, y, final_color)
	
	# Verify no hard edges by smoothing the atmosphere's edge
	for y in range(atm_size):
		for x in range(atm_size):
			var pos = Vector2(x, y)
			var dist = pos.distance_to(center)
			
			# Only process the edge area
			if dist > outer_radius - 2.0 and dist < outer_radius + 2.0:
				var t = (dist - (outer_radius - 2.0)) / 4.0  # 0 to 1 in the 4 pixel transition
				t = clamp(t, 0.0, 1.0)
				t = t * t * (3.0 - 2.0 * t)  # Smooth step
				
				var pixel_color = image.get_pixel(x, y)
				pixel_color.a *= 1.0 - t
				
				image.set_pixel(x, y, pixel_color)
	
	return ImageTexture.create_from_image(image)

# Convert planet type to atmosphere color
func get_atmosphere_color_for_theme(theme: int) -> Color:
	return ATMOSPHERE_COLORS.get(theme, Color(0.5, 0.7, 0.9, 0.3))  # Default to light blue

# Convert planet type to atmosphere thickness
func get_atmosphere_thickness_for_theme(theme: int) -> float:
	return ATMOSPHERE_THICKNESS.get(theme, 1.0)  # Default to normal thickness
