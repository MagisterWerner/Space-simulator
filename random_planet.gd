extends Node2D

# Realistic Procedural Planet Generator
# Planetary terrain generation system with atmosphere

# Represents different planetary types with unique geological characteristics
enum PlanetTheme {
	ARID,       # Desert-like, sandy colors
	ICE,        # Cold, bluish-white palette
	LAVA,       # Volcanic, red and orange hues
	LUSH,       # Green and blue, vegetation-like
	ROCKY,      # Gray and brown, mineral-rich
	DESERT,     # Dry, sandy, with rock formations
	ALPINE,     # Mountain and snow-capped terrain
	SUNSET,     # Warm-toned, with sunset-like coloration
	OCEAN       # Predominantly water-based world
}

# Planet characteristics
var planet_size: int = 400  # Display size of the planet
var pixel_resolution: int = 256  # Increased resolution for better detail
var seed_value: int = 0  # Base randomization seed
var current_theme: PlanetTheme = PlanetTheme.ARID

# Debug label to display current planet theme
var theme_label: Label

# Terrain Configuration
var terrain_size: float = 8.0  # Base terrain feature size
var terrain_octaves: int = 6  # Noise complexity
var light_origin: Vector2 = Vector2(0.39, 0.39)  # Light source position

# Atmosphere parameters - Improved rendering
const ATMOSPHERE_THICKNESS: float = 1.0  # More pronounced atmosphere thickness
const ATMOSPHERE_INTENSITY: float = 0.5  # Slightly more transparent atmosphere
const BASE_PLANET_RADIUS_FACTOR: float = 0.42  # Adjusted base planet size

# Global variables for planet generation
var planet_radius_factor: float = BASE_PLANET_RADIUS_FACTOR
var last_size_percentage: int = 100

# Function to update planet size factor based on seed
func update_planet_size_factor() -> void:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	# Generate a whole number percentage (100-150)
	var size_percentage = rng.randi_range(100, 150)
	
	# Avoid repeating the same size
	if size_percentage == last_size_percentage:
		size_percentage = (size_percentage + rng.randi_range(5, 15)) % 51 + 100
	
	# Save for next time
	last_size_percentage = size_percentage
	
	# Convert to scaling factor
	var size_factor = float(size_percentage) / 100.0
	
	# Apply to planet radius
	planet_radius_factor = BASE_PLANET_RADIUS_FACTOR * size_factor
	
	print("Planet size: ", size_percentage, "% of base size")

# Get planet size as percentage
func get_planet_size_percentage() -> int:
	return last_size_percentage

# Pseudo-random number generation with consistent geological behavior
func get_random_seed(x: float, y: float) -> float:
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(str(seed_value) + str(x) + str(y))
	return rng.randf()

# Interpolated noise generation
func noise(x: float, y: float) -> float:
	var ix = floor(x)
	var iy = floor(y)
	var fx = x - ix
	var fy = y - iy
	
	var cubic_x = fx * fx * (3.0 - 2.0 * fx)
	var cubic_y = fy * fy * (3.0 - 2.0 * fy)
	
	var a = get_random_seed(ix, iy)
	var b = get_random_seed(ix + 1.0, iy)
	var c = get_random_seed(ix, iy + 1.0)
	var d = get_random_seed(ix + 1.0, iy + 1.0)
	
	return lerp(
		lerp(a, b, cubic_x),
		lerp(c, d, cubic_x),
		cubic_y
	)

# Fractal Brownian Motion (fBm) terrain generation
func fbm(x: float, y: float, octaves: int = 6, variation: float = 1.0) -> float:
	var value = 0.0
	var amplitude = 0.5
	var frequency = terrain_size * variation
	
	for _i in range(octaves):
		value += noise(x * frequency, y * frequency) * amplitude
		frequency *= 2.0
		amplitude *= 0.5
	
	return value

# Sophisticated spherical coordinate mapping
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

# Generate sophisticated color palettes for different planetary themes
func generate_planet_palette(theme: PlanetTheme) -> PackedColorArray:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	match theme:
		PlanetTheme.ARID:
			return PackedColorArray([
				Color(0.7, 0.5, 0.3),   # Light sand
				Color(0.6, 0.4, 0.2),   # Dark sand
				Color(0.8, 0.6, 0.4),   # Sandy base
				Color(0.5, 0.3, 0.2),   # Deep rocky terrain
				Color(0.4, 0.3, 0.1),   # Dark rocky ground
				Color(0.9, 0.7, 0.5)    # Highlight rocky hills
			])
		
		PlanetTheme.LAVA:
			return PackedColorArray([
				Color(1.0, 0.3, 0.0),   # Bright lava
				Color(0.8, 0.2, 0.0),   # Dark lava base
				Color(0.6, 0.1, 0.0),   # Cooled lava
				Color(0.4, 0.1, 0.0),   # Volcanic rock
				Color(0.9, 0.4, 0.1),   # Lava glow
				Color(0.3, 0.1, 0.0)    # Deep volcanic trenches
			])
		
		PlanetTheme.LUSH:
			return PackedColorArray([
				Color(0.2, 0.6, 0.2),   # Bright green vegetation
				Color(0.1, 0.5, 0.1),   # Dark forest green
				Color(0.3, 0.7, 0.3),   # Lime green
				Color(0.3, 0.5, 0.7),   # Water regions
				Color(0.2, 0.4, 0.2),   # Deep forest
				Color(0.4, 0.8, 0.4)    # Bright mountain highlands
			])
		
		PlanetTheme.ICE:
			return PackedColorArray([
				Color(0.9, 0.95, 1.0),  # Bright white ice
				Color(0.6, 0.8, 1.0),   # Light blue glacial
				Color(0.7, 0.85, 0.95), # Pale blue
				Color(0.4, 0.6, 0.8),   # Deep ice
				Color(0.8, 0.9, 1.0),   # Snow regions
				Color(0.5, 0.7, 0.9)    # Icy mountain peaks
			])
		
		PlanetTheme.ROCKY:
			return PackedColorArray([
				Color(0.6, 0.5, 0.4),   # Light stone
				Color(0.5, 0.4, 0.3),   # Brownish gray
				Color(0.7, 0.6, 0.5),   # Warm stone
				Color(0.4, 0.3, 0.2),   # Dark stone
				Color(0.8, 0.7, 0.6),   # Sandy rock
				Color(0.3, 0.2, 0.1)    # Deep rocky canyons
			])
		
		PlanetTheme.DESERT:
			return PackedColorArray([
				Color(0.9, 0.8, 0.5),   # Light sand dunes
				Color(0.8, 0.7, 0.4),   # Warm sand
				Color(0.7, 0.6, 0.3),   # Sandy plateaus
				Color(0.6, 0.5, 0.2),   # Rocky outcrops
				Color(0.5, 0.4, 0.1),   # Deep desert terrain
				Color(0.4, 0.3, 0.0)    # Dark rocky formations
			])
		
		PlanetTheme.ALPINE:
			return PackedColorArray([
				Color(0.9, 0.9, 1.0),   # Snow-capped peaks
				Color(0.6, 0.7, 0.6),   # Rocky mountain slopes
				Color(0.4, 0.5, 0.4),   # Mountain forest
				Color(0.7, 0.8, 0.7),   # Alpine meadows
				Color(0.5, 0.6, 0.5),   # Mountain stone
				Color(0.8, 0.9, 0.8)    # Bright mountain tops
			])
		
		PlanetTheme.SUNSET:
			return PackedColorArray([
				Color(1.0, 0.6, 0.3),   # Bright sunset orange
				Color(0.9, 0.5, 0.2),   # Deep sunset base
				Color(0.8, 0.4, 0.1),   # Dark sunset tones
				Color(0.7, 0.3, 0.2),   # Rich sunset crimson
				Color(0.6, 0.2, 0.1),   # Deep sunset horizon
				Color(0.5, 0.1, 0.0)    # Dark sunset valleys
			])
		
		PlanetTheme.OCEAN:
			return PackedColorArray([
				Color(0.1, 0.4, 0.7),   # Deep ocean blue
				Color(0.2, 0.5, 0.8),   # Mid-ocean blue
				Color(0.3, 0.6, 0.9),   # Light ocean blue
				Color(0.4, 0.7, 1.0),   # Shallow water
				Color(0.5, 0.8, 1.0),   # Tropical water
				Color(0.6, 0.9, 1.0)    # Bright coastal regions
			])
		
		_:
			return PackedColorArray([
				Color(0.5, 0.5, 0.5),
				Color(0.6, 0.6, 0.6),
				Color(0.4, 0.4, 0.4),
				Color(0.7, 0.7, 0.7),
				Color(0.3, 0.3, 0.3),
				Color(0.8, 0.8, 0.8)
			])

# Get atmosphere color with more nuanced approach
func get_atmosphere_color(theme: PlanetTheme) -> Color:
	match theme:
		PlanetTheme.LUSH:
			return Color(0.4, 0.7, 1.0, 1.0)  # Soft blue-green atmosphere
		PlanetTheme.OCEAN:
			return Color(0.3, 0.6, 1.0, 1.0)  # Deep marine blue atmosphere
		PlanetTheme.ICE:
			return Color(0.6, 0.8, 1.0, 1.0)  # Pale blue atmosphere
		PlanetTheme.ALPINE:
			return Color(0.5, 0.7, 1.0, 1.0)  # Mountain blue atmosphere
		PlanetTheme.LAVA:
			return Color(1.0, 0.4, 0.1, 1.0)  # Deep orange-red atmosphere
		PlanetTheme.DESERT:
			return Color(0.9, 0.7, 0.4, 1.0)  # Beige-brown atmosphere
		PlanetTheme.ARID:
			return Color(0.8, 0.6, 0.3, 1.0)  # Sandy brown atmosphere
		PlanetTheme.SUNSET:
			return Color(0.9, 0.5, 0.2, 1.0)  # Burnt orange atmosphere
		PlanetTheme.ROCKY:
			return Color(0.7, 0.5, 0.3, 1.0)  # Soft brown atmosphere
		_:
			return Color(0.6, 0.9, 1.0, 1.0)  # Default blue-ish atmosphere

# Create planet texture with improved atmosphere rendering
func create_planet_texture() -> Array:
	var final_resolution = pixel_resolution
	var image = Image.create(final_resolution, final_resolution, false, Image.FORMAT_RGBA8)
	var atmosphere_image = Image.create(final_resolution, final_resolution, true, Image.FORMAT_RGBA8)
	
	# Generate color palette for current theme
	var colors = generate_planet_palette(current_theme)
	var atmosphere_color = get_atmosphere_color(current_theme)
	
	# Calculate atmosphere parameters
	var planet_radius = planet_radius_factor
	var atmosphere_radius = planet_radius * (1.0 + ATMOSPHERE_THICKNESS)
	
	# Generate planet surface and atmosphere
	for x in range(final_resolution):
		for y in range(final_resolution):
			# Normalize coordinates
			var nx = float(x) / (final_resolution - 1)
			var ny = float(y) / (final_resolution - 1)
			
			# Calculate distance from center
			var dx = nx - 0.5
			var dy = ny - 0.5
			var d_circle = sqrt(dx * dx + dy * dy) * 2.0
			
			# Atmospheric rendering with more pronounced edge
			if d_circle > planet_radius and d_circle <= atmosphere_radius:
				# Create a more gradual and visible atmospheric transition
				var atmos_distance = (d_circle - planet_radius) / (atmosphere_radius - planet_radius)
				
				# More sophisticated power curve for atmospheric effect
				var atmos_alpha = pow(1.0 - atmos_distance, 4) * ATMOSPHERE_INTENSITY
				
				var pixel_atmosphere = atmosphere_color
				
				# Enhanced gradient effect with non-linear alpha falloff
				pixel_atmosphere.a = atmos_alpha * (1.0 - pow(atmos_distance, 0.5))
				
				atmosphere_image.set_pixel(x, y, pixel_atmosphere)
				continue
			
			# Skip pixels completely outside the atmosphere
			if d_circle > atmosphere_radius:
				continue
			
			# Spherify coordinates for natural planetary mapping
			var sphere_uv = spherify(nx, ny)
			
			# Generate multiple noise layers for complex terrain
			var base_noise = fbm(sphere_uv.x, sphere_uv.y, terrain_octaves)
			var detail_noise = fbm(sphere_uv.x * 2.0, sphere_uv.y * 2.0, max(2, terrain_octaves - 2), 1.5)
			
			# Combine noise layers for rich terrain variation
			var combined_noise = base_noise * 0.7 + detail_noise * 0.3
			
			# Color mapping with terrain variation
			var color_index = floor(combined_noise * colors.size())
			color_index = clamp(color_index, 0, colors.size() - 1)
			
			# Final color with terrain detail
			var final_color = colors[color_index]
			
			# Add depth and lighting simulation
			var edge_shade = 1.0 - pow(d_circle * 2, 2)
			final_color *= 0.8 + edge_shade * 0.2
			
			image.set_pixel(x, y, final_color)
	
	return [
		ImageTexture.create_from_image(image),         # Planet texture
		ImageTexture.create_from_image(atmosphere_image) # Atmosphere texture
	]

# Scene setup with planet generation and debug label
func _ready():
	# Make sure planet size is updated before creating textures
	update_planet_size_factor()
	
	var textures = create_planet_texture()
	var planet_texture = textures[0]
	var atmosphere_texture = textures[1]
	
	# Calculate dynamic container size based on planet radius
	var display_size = int(planet_size * (last_size_percentage / 100.0))
	
	# Planet container for proper layering
	var planet_container = Node2D.new()
	planet_container.position = (get_viewport_rect().size - Vector2(display_size, display_size)) / 2
	
	# Planet base
	var planet_texture_rect = TextureRect.new()
	planet_texture_rect.texture = planet_texture
	planet_texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	planet_texture_rect.custom_minimum_size = Vector2(display_size, display_size)
	
	# Atmosphere layer
	var atmosphere_texture_rect = TextureRect.new()
	atmosphere_texture_rect.texture = atmosphere_texture
	atmosphere_texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	atmosphere_texture_rect.custom_minimum_size = Vector2(display_size, display_size)
	
	# Add planet and atmosphere to container
	planet_container.add_child(planet_texture_rect)
	planet_container.add_child(atmosphere_texture_rect)
	add_child(planet_container)
	
	# Debug label configuration
	theme_label = Label.new()
	theme_label.text = "Theme: " + PlanetTheme.keys()[current_theme] + " (Size: " + str(get_planet_size_percentage()) + "%)"
	theme_label.position = Vector2(10, 10)
	theme_label.add_theme_color_override("font_color", Color.WHITE)
	theme_label.add_theme_font_size_override("font_size", 20)
	
	# Semi-transparent background for label readability
	var label_background = ColorRect.new()
	label_background.color = Color(0, 0, 0, 0.5)
	label_background.size = Vector2(250, 40)  # Made wider to fit more text
	label_background.position = theme_label.position
	
	add_child(label_background)
	add_child(theme_label)

# Regenerate planet on spacebar press
func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		seed_value = randi()  # Completely randomize the seed
		current_theme = PlanetTheme.values()[randi() % PlanetTheme.size()]
		
		# Force update of planet radius to ensure it changes every time
		update_planet_size_factor()
		
		# Regenerate planet and atmosphere textures
		var textures = create_planet_texture()
		var planet_container = get_child(get_child_count() - 3)  # Get the planet container
		
		# Update planet texture
		planet_container.get_child(0).texture = textures[0]
		# Update atmosphere texture
		planet_container.get_child(1).texture = textures[1]
		
		# Update theme label and include planet size info
		if theme_label:
			theme_label.text = "Theme: " + PlanetTheme.keys()[current_theme] + " (Size: " + str(get_planet_size_percentage()) + "%)"
			print("Regenerated planet with seed:", seed_value, "and size:", get_planet_size_percentage(), "%")

# Initialize planet with current inspector settings
func _enter_tree():
	# Only randomize seed if it's 0 (not manually set)
	if seed_value == 0:
		seed_value = randi()
	
	# Keep the theme from the inspector, don't randomize it
	
	# Initialize planet size factor
	update_planet_size_factor()
