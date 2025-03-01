extends Node2D

# Realistic Procedural Planet Generator
# Planetary terrain generation system with atmosphere

# Represents different planetary types with unique geological characteristics
enum PlanetTheme {
	ARID,       # Desert-like, sandy colors
	ICE,        # Cold, bluish-white palette
	LAVA,       # Volcanic, red and orange hues
	LUSH,       # Green and blue, vegetation-like
	DESERT,     # Dry, sandy, with rock formations
	ALPINE,     # Mountain and snow-capped terrain with forests
	OCEAN       # Predominantly water-based world
}

# Planet characteristics
var planet_size: int = 128  # Display size of the planet
var pixel_resolution: int = 192  # Resolution for detail
var seed_value: int = 0  # Base randomization seed
var current_theme: PlanetTheme = PlanetTheme.ARID

# Terrain Configuration
var terrain_size: float = 8.0  # Base terrain feature size
var terrain_octaves: int = 6  # Noise complexity
var light_origin: Vector2 = Vector2(0.39, 0.39)  # Light source position

# Atmosphere parameters
const ATMOSPHERE_THICKNESS: float = 1.0
const ATMOSPHERE_INTENSITY: float = 0.5
const BASE_PLANET_RADIUS_FACTOR: float = 0.42

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
	
	# Apply to planet radius
	planet_radius_factor = BASE_PLANET_RADIUS_FACTOR * (float(size_percentage) / 100.0)

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

# Generate color palettes for different planetary themes
func generate_planet_palette(theme: PlanetTheme) -> PackedColorArray:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	match theme:
		PlanetTheme.ARID:
			return PackedColorArray([
				Color(0.82, 0.58, 0.35),  # Light sand with red tint
				Color(0.70, 0.42, 0.25),  # Dark sand with red tint
				Color(0.63, 0.38, 0.22),  # Sandy base with red tint
				Color(0.53, 0.30, 0.16),  # Deep rocky terrain with red tint
				Color(0.40, 0.23, 0.12)   # Dark rocky ground with red tint
			])
		
		PlanetTheme.LAVA:
			return PackedColorArray([
				Color(1.0, 0.6, 0.0),     # Single bright orange for lava lakes
				Color(0.7, 0.1, 0.05),    # Dark red lava
				Color(0.55, 0.08, 0.04),  # Deeper red lava
				Color(0.4, 0.06, 0.03),   # Very dark red terrain
				Color(0.25, 0.04, 0.02)   # Nearly black volcanic rock
			])
		
		PlanetTheme.LUSH:
			return PackedColorArray([
				Color(0.2, 0.7, 0.3),     # Bright vibrant green
				Color(0.1, 0.5, 0.1),     # Dark forest green
				Color(0.3, 0.5, 0.7),     # Blue water regions
				Color(0.25, 0.6, 0.25),   # Mid-tone vegetation
				Color(0.15, 0.4, 0.15)    # Deep forest shadow
			])
		
		PlanetTheme.ICE:
			return PackedColorArray([
				Color(0.92, 0.97, 1.0),   # Bright white ice
				Color(0.75, 0.85, 0.95),  # Light blue glacial
				Color(0.60, 0.75, 0.90),  # Deeper glacial blue
				Color(0.45, 0.65, 0.85),  # Deep ice
				Color(0.30, 0.50, 0.75)   # Glacial crevasses
			])
		
		PlanetTheme.DESERT:
			return PackedColorArray([
				Color(0.88, 0.72, 0.45),  # Light sand dunes
				Color(0.80, 0.65, 0.38),  # Warm sand
				Color(0.70, 0.55, 0.30),  # Sandy plateaus
				Color(0.60, 0.45, 0.25),  # Rocky outcrops
				Color(0.48, 0.35, 0.20)   # Deep desert terrain
			])
		
		PlanetTheme.ALPINE:
			return PackedColorArray([
				Color(0.98, 0.98, 0.98),  # Pure white snow
				Color(0.90, 0.90, 0.95),  # Bright white snow
				Color(0.85, 0.85, 0.90),  # Light grey snow
				Color(0.75, 0.85, 0.75),  # Snow-covered forests (white-green)
				Color(0.65, 0.75, 0.65)   # Light snow-dusted forests
			])
		
		PlanetTheme.OCEAN:
			return PackedColorArray([
				Color(0.10, 0.35, 0.65),  # Deep ocean blue
				Color(0.15, 0.45, 0.75),  # Mid-ocean blue
				Color(0.20, 0.55, 0.85),  # Light ocean blue
				Color(0.30, 0.65, 0.90),  # Shallow water
				Color(0.40, 0.75, 0.95)   # Coastal waters
			])
		
		_:
			return PackedColorArray([
				Color(0.5, 0.5, 0.5),
				Color(0.6, 0.6, 0.6),
				Color(0.4, 0.4, 0.4),
				Color(0.7, 0.7, 0.7),
				Color(0.3, 0.3, 0.3)
			])

# Get atmosphere color with more realistic approach
func get_atmosphere_color(theme: PlanetTheme) -> Color:
	match theme:
		PlanetTheme.LUSH:
			return Color(0.35, 0.60, 0.90, 1.0)  # Blue with hint of green
		PlanetTheme.OCEAN:
			return Color(0.25, 0.55, 0.95, 1.0)  # Deep blue atmosphere
		PlanetTheme.ICE:
			return Color(0.65, 0.78, 0.95, 1.0)  # Pale blue atmosphere
		PlanetTheme.ALPINE:
			return Color(0.80, 0.82, 0.85, 1.0)  # Light grey with hint of blue
		PlanetTheme.LAVA:
			return Color(0.65, 0.15, 0.05, 1.0)  # Dark red atmosphere with slight orange tint
		PlanetTheme.DESERT:
			return Color(0.85, 0.65, 0.35, 1.0)  # Tan/brown atmosphere
		PlanetTheme.ARID:
			return Color(0.80, 0.45, 0.25, 1.0)  # Dusty red atmosphere
		_:
			return Color(0.60, 0.70, 0.90, 1.0)  # Default atmosphere

# Create planet texture with atmosphere rendering
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
			
			# Atmospheric rendering
			if d_circle > planet_radius and d_circle <= atmosphere_radius:
				var atmos_distance = (d_circle - planet_radius) / (atmosphere_radius - planet_radius)
				var atmos_alpha = pow(1.0 - atmos_distance, 4) * ATMOSPHERE_INTENSITY
				var pixel_atmosphere = atmosphere_color
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
		ImageTexture.create_from_image(image),
		ImageTexture.create_from_image(atmosphere_image)
	]

# Scene setup with planet generation
func _ready():
	update_planet_size_factor()
	
	var textures = create_planet_texture()
	var planet_texture = textures[0]
	var atmosphere_texture = textures[1]
	
	# Calculate dynamic container size based on planet radius
	var display_size = int(planet_size * (last_size_percentage / 100.0))
	
	# Planet container for layering
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

# Regenerate planet on spacebar press
func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		seed_value = randi()
		current_theme = PlanetTheme.values()[randi() % PlanetTheme.size()]
		
		update_planet_size_factor()
		
		var textures = create_planet_texture()
		var planet_container = get_child(0)
		
		# Update planet texture
		planet_container.get_child(0).texture = textures[0]
		# Update atmosphere texture
		planet_container.get_child(1).texture = textures[1]

# Initialize planet with current inspector settings
func _enter_tree():
	# Only randomize seed if it's 0 (not manually set)
	if seed_value == 0:
		seed_value = randi()
	
	# Initialize planet size factor
	update_planet_size_factor()
