# scripts/generators/asteroid_generator.gd - Optimized asteroid texture generator
extends Node2D

signal texture_generated(texture)

# Asteroid size constants
const ASTEROID_SIZE_SMALL: int = 16
const ASTEROID_SIZE_MEDIUM: int = 32
const ASTEROID_SIZE_LARGE: int = 64

# Texture resolution constants
const CUBIC_RESOLUTION: int = 32
const PIXEL_RESOLUTION: int = 64
const HIGH_RESOLUTION: int = 128
const ULTRA_RESOLUTION: int = 256

# Asteroid shape parameters with clear defaults
@export var irregularity: float = 0.4  # How jagged the asteroid is (0-1)
@export var irregularity_detail: float = 1.4  # Fine detail level for edges
@export var elongation: float = 0.3  # How stretched the asteroid is (0-1)
@export var boundary_smoothing: int = 6  # How smooth the outline is
@export var asymmetry_strength: float = 0.5  # How asymmetrical the asteroid is (0-1)
@export var resolution: int = PIXEL_RESOLUTION  # Texture resolution
@export var noise_frequency: float = 8.0  # Base noise frequency
@export var noise_octaves: int = 3  # Number of noise octaves

# Crater parameters
@export var crater_count_min: int = 1
@export var crater_count_max: int = 3
@export var crater_depth_min: float = 0.25
@export var crater_depth_max: float = 0.5
@export var crater_irregularity: float = 0.3
@export var crater_overlap_prevention: float = 1.1

# Lighting parameters
@export var light_direction: Vector2 = Vector2(-0.5, -0.8)
@export var ambient_light: float = 0.6
@export var light_intensity: float = 0.4
@export var enhanced_lighting: bool = true

# Color and appearance settings
@export_category("Appearance")
@export var color_palette: PackedColorArray = PackedColorArray([
	Color(0.25, 0.24, 0.24),  # Dark gray
	Color(0.20, 0.19, 0.19),  # Medium dark gray
	Color(0.16, 0.15, 0.15),  # Medium gray
	Color(0.12, 0.11, 0.11),  # Light gray
	Color(0.10, 0.09, 0.09)   # Very light gray
])
@export var edge_darkening: float = 0.15  # Darkening applied to edges (0-1)

# Performance options
@export_category("Performance")
@export var use_cached_lookups: bool = true
@export var simplify_small_asteroids: bool = true
@export var use_noise_generator: bool = true

# Generator state
var seed_value: int = 0
var main_rng: RandomNumberGenerator
var noise_generator: FastNoiseLite
var boundary_values: PackedFloat32Array = PackedFloat32Array()
var craters: Array[Dictionary] = []

# Lookup tables and caching
var cubic_lookup: PackedFloat32Array = PackedFloat32Array()
var sin_table: PackedFloat32Array = PackedFloat32Array()
var cos_table: PackedFloat32Array = PackedFloat32Array()
var noise_cache: Dictionary = {}

# Texture caching for performance
static var texture_cache: Dictionary = {}
static var last_texture_cleanup: int = 0
const MAX_TEXTURE_CACHE_SIZE: int = 50

func _init() -> void:
	# Initialize RNG
	main_rng = RandomNumberGenerator.new()
	seed_value = randi()
	main_rng.seed = seed_value
	
	# Initialize noise generator
	noise_generator = FastNoiseLite.new()
	noise_generator.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_generator.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise_generator.fractal_octaves = noise_octaves
	noise_generator.fractal_lacunarity = 2.0
	noise_generator.fractal_gain = 0.5
	
	# Normalize light direction
	light_direction = light_direction.normalized()
	
	# Pre-compute lookup tables if enabled
	if use_cached_lookups:
		_precompute_lookup_tables()

func _precompute_lookup_tables() -> void:
	# Cubic interpolation lookup table
	cubic_lookup.resize(CUBIC_RESOLUTION)
	for i in range(CUBIC_RESOLUTION):
		var t = float(i) / (CUBIC_RESOLUTION - 1)
		cubic_lookup[i] = t * t * (3.0 - 2.0 * t)
	
	# Sine and cosine tables (360 degrees)
	sin_table.resize(360)
	cos_table.resize(360)
	for i in range(360):
		var angle = deg_to_rad(i)
		sin_table[i] = sin(angle)
		cos_table[i] = cos(angle)

func _ready() -> void:
	# Set an initial random seed
	randomize()
	seed_value = randi()
	
	# Add to planet_spawners group for cache clearing
	add_to_group("planet_spawners")
	
	# Initialize texture cache cleanup timer
	var timer = Timer.new()
	timer.wait_time = 60.0  # Check cache size every minute
	timer.autostart = true
	timer.timeout.connect(_check_texture_cache)
	add_child(timer)

func _check_texture_cache() -> void:
	var current_time = Time.get_ticks_msec()
	
	# Only clean every 60 seconds
	if current_time - last_texture_cleanup < 60000:
		return
	
	last_texture_cleanup = current_time
	
	# Clean if cache exceeds limit
	if texture_cache.size() > MAX_TEXTURE_CACHE_SIZE:
		var keys = texture_cache.keys()
		keys.sort()  # Deterministic sort for consistent cleanup
		
		# Remove oldest entries until under limit
		for i in range(keys.size() - MAX_TEXTURE_CACHE_SIZE):
			texture_cache.erase(keys[i])

# Set a specific seed for deterministic generation
func set_seed(new_seed: int) -> void:
	seed_value = new_seed
	main_rng.seed = new_seed
	noise_generator.seed = new_seed
	noise_cache.clear()

# Get cubic interpolation factor
func get_cubic(t: float) -> float:
	if use_cached_lookups:
		var index = int(t * (CUBIC_RESOLUTION - 1))
		index = clamp(index, 0, CUBIC_RESOLUTION - 1)
		return cubic_lookup[index]
	else:
		# Calculate on-the-fly
		return t * t * (3.0 - 2.0 * t)

# Generate deterministic random value for coordinates
func get_random_seed(x: int, y: int) -> float:
	var key = x << 16 | (y & 0xFFFF)  # Bit-pack coordinates
	
	if noise_cache.has(key):
		return noise_cache[key]
	
	main_rng.seed = hash([seed_value, x, y])
	var value = main_rng.randf()
	noise_cache[key] = value
	return value

# Coherent noise function
func noise(x: float, y: float) -> float:
	# Use FastNoiseLite for better quality and performance
	if use_noise_generator:
		return (noise_generator.get_noise_2d(x, y) + 1.0) * 0.5
	
	# Manual implementation for perfect compatibility
	var ix = int(floor(x))
	var iy = int(floor(y))
	var fx = x - ix
	var fy = y - iy
	
	var cubic_x = get_cubic(fx)
	var cubic_y = get_cubic(fy)
	
	var a = get_random_seed(ix, iy)
	var b = get_random_seed(ix + 1, iy)
	var c = get_random_seed(ix, iy + 1)
	var d = get_random_seed(ix + 1, iy + 1)
	
	return lerp(
		lerp(a, b, cubic_x),
		lerp(c, d, cubic_x),
		cubic_y
	)

# Fractal Brownian Motion noise
func fbm(x: float, y: float) -> float:
	# Use built-in fbm from noise generator
	if use_noise_generator:
		noise_generator.seed = seed_value
		return (noise_generator.get_noise_2d(x * noise_frequency, y * noise_frequency) + 1.0) * 0.5
	
	# Manual implementation for compatibility
	var value = 0.0
	var amplitude = 0.5
	var frequency = noise_frequency
	
	for _i in range(noise_octaves):
		value += noise(x * frequency, y * frequency) * amplitude
		frequency *= 2.0
		amplitude *= 0.5
	
	return value

# Generate boundary noise for asteroid edge
func boundary_noise(angle: float) -> float:
	var x = cos(angle) * irregularity_detail
	var y = sin(angle) * irregularity_detail
	
	var boundary_value = noise(x, y) * irregularity
	boundary_value += noise(x * 2.0, y * 2.0) * (irregularity * 0.4)
	boundary_value += noise(x * 4.0, y * 4.0) * (irregularity * 0.15)
	
	var large_scale_variation = sin(angle * 1.5) * cos(angle * 0.5) * irregularity * asymmetry_strength
	large_scale_variation += sin(angle * 2.3) * cos(angle * 1.7) * irregularity * asymmetry_strength * 0.7
	boundary_value += large_scale_variation
	
	return 1.0 - irregularity + boundary_value

# Smooth the boundary values for a less jagged appearance
func smooth_boundary_values() -> void:
	var smoothed = PackedFloat32Array()
	smoothed.resize(boundary_values.size())
	
	var window_size = boundary_smoothing
	var size = boundary_values.size()
	
	for _smoothing_pass in range(2):
		for i in range(size):
			var sum = 0.0
			
			for j in range(-window_size, window_size + 1):
				var index = (i + j) % size
				if index < 0:
					index += size
				sum += boundary_values[index]
			
			smoothed[i] = sum / (2 * window_size + 1)
		
		# Copy all at once
		for i in range(size):
			boundary_values[i] = smoothed[i]

# Apply elongation to create stretched asteroids
func apply_elongation(point: Vector2) -> Vector2:
	if elongation <= 0.05:
		return point
	
	var angle = main_rng.randf() * TAU
	
	var cos_angle = cos(-angle)
	var sin_angle = sin(-angle)
	
	var rotated_x = point.x * cos_angle - point.y * sin_angle
	var rotated_y = point.x * sin_angle + point.y * cos_angle
	
	var stretch_x = 1.0 + elongation
	var stretch_y = 1.0 - elongation * 0.6
	
	if point.x > 0:
		stretch_x *= (1.0 + main_rng.randf_range(-0.1, 0.2) * elongation)
	if point.y > 0:
		stretch_y *= (1.0 + main_rng.randf_range(-0.1, 0.2) * elongation)
	
	rotated_x *= stretch_x
	rotated_y *= stretch_y
	
	var radius = sqrt(rotated_x * rotated_x + rotated_y * rotated_y)
	var distortion_angle = atan2(rotated_y, rotated_x)
	
	var angular_distortion = sin(distortion_angle * 3.0) * 0.15 * elongation
	var x_distortion = cos(angular_distortion * PI) * radius * 0.15
	var y_distortion = sin(angular_distortion * PI) * radius * 0.15
	
	rotated_x += x_distortion
	rotated_y += y_distortion
	
	var result_x = rotated_x * cos(angle) - rotated_y * sin(angle)
	var result_y = rotated_x * sin(angle) + rotated_y * cos(angle)
	
	return Vector2(result_x, result_y)

# Convert flat coordinates to spherical projection
func spherify(x: float, y: float) -> Vector2:
	var centered_x = x * 2.0 - 1.0
	var centered_y = y * 2.0 - 1.0
	
	var elongated = apply_elongation(Vector2(centered_x, centered_y))
	centered_x = elongated.x
	centered_y = elongated.y
	
	var length_squared = centered_x * centered_x + centered_y * centered_y
	
	if length_squared >= 1.0:
		return Vector2(x, y)
	
	var z = sqrt(1.0 - length_squared)
	var z_plus_one = z + 1.0
	
	return Vector2(
		(centered_x / z_plus_one + 1.0) * 0.5,
		(centered_y / z_plus_one + 1.0) * 0.5
	)

# Check if a crater would overlap with existing craters
func is_crater_overlapping(new_crater: Dictionary) -> bool:
	var new_center_x = new_crater.center_x
	var new_center_y = new_crater.center_y
	var new_size = new_crater.size
	
	for existing_crater in craters:
		var center_dx = new_center_x - existing_crater.center_x
		var center_dy = new_center_y - existing_crater.center_y
		var center_distance_sq = center_dx * center_dx + center_dy * center_dy
		
		var min_distance = (new_size + existing_crater.size) * crater_overlap_prevention
		var min_distance_sq = min_distance * min_distance
		
		if center_distance_sq < min_distance_sq:
			return true
	
	return false

# Generate craters for the asteroid
func generate_craters() -> void:
	craters.clear()
	
	# Determine crater count based on current seed
	var crater_count = main_rng.randi_range(crater_count_min, crater_count_max)
	var max_attempts = crater_count * 10
	var attempts = 0
	
	# Calculate crater size range
	var crater_size_min = 0.06
	var crater_size_max = 0.12
	
	while craters.size() < crater_count and attempts < max_attempts:
		var angle = main_rng.randf_range(0, TAU)
		var radius = main_rng.randf_range(0.2, 0.8)
		
		var center_x = 0.5 + cos(angle) * radius * 0.5
		var center_y = 0.5 + sin(angle) * radius * 0.5
		
		var size = main_rng.randf_range(crater_size_min, crater_size_max)
		var depth = main_rng.randf_range(crater_depth_min, crater_depth_max)
		
		var new_crater = {
			"center_x": center_x,
			"center_y": center_y,
			"size": size,
			"depth": depth,
			"noise_freq": main_rng.randf_range(2.0, 4.0),
			"noise_amp": main_rng.randf_range(0.1, crater_irregularity),
			"angle": main_rng.randf_range(0, TAU),
			"elongation": main_rng.randf_range(0.0, 0.2),
		}
		
		if not is_crater_overlapping(new_crater):
			craters.append(new_crater)
		
		attempts += 1

# Get crater shape factor
func get_crater_shape_factor(crater: Dictionary, angle: float, distance_normalized: float) -> float:
	var noise_x = cos(angle) * crater.noise_freq
	var noise_y = sin(angle) * crater.noise_freq
	
	var shape_noise = noise(noise_x, noise_y) * crater.noise_amp
	
	if crater.size > 0.1:  # For larger craters, add more detail
		shape_noise += noise(noise_x * 2.0, noise_y * 2.0) * (crater.noise_amp * 0.5)
	
	var shape_factor = 1.0 + shape_noise * distance_normalized
	
	if crater.elongation > 0.05:
		var elongation_angle = crater.angle
		var dx = cos(angle - elongation_angle)
		shape_factor *= (1.0 + dx * crater.elongation)
	
	return shape_factor

# Calculate depth at a point due to craters
func calculate_crater_depth(crater: Dictionary, nx: float, ny: float) -> float:
	var dx = nx - crater.center_x
	var dy = ny - crater.center_y
	var distance_sq = dx * dx + dy * dy
	var crater_size_sq = crater.size * crater.size
	
	if distance_sq > crater_size_sq:
		return 0.0
	
	var distance = sqrt(distance_sq)
	var angle = atan2(dy, dx)
	if angle < 0:
		angle += TAU
	
	var distance_normalized = distance / crater.size
	var shape_factor = get_crater_shape_factor(crater, angle, distance_normalized)
	
	if distance_normalized > shape_factor:
		return 0.0
	
	var shaped_distance = distance_normalized / shape_factor
	var depth_factor = 0.0
	
	if shaped_distance < 0.2:
		var floor_factor = pow(shaped_distance / 0.2, 0.7)
		depth_factor = -crater.depth * (0.85 + floor_factor * 0.15)
	elif shaped_distance < 0.85:
		var wall_factor = (shaped_distance - 0.2) / 0.65
		var slope = pow(wall_factor, 0.9)
		depth_factor = -crater.depth * (1.0 - slope) * 0.85
	else:
		var rim_factor = (shaped_distance - 0.85) / 0.15
		depth_factor = crater.depth * 0.04 * (1.0 - rim_factor) * (1.0 - rim_factor)
	
	return depth_factor

# Calculate normal vector at a point on the asteroid surface
func calculate_surface_normal(depth_map: PackedFloat32Array, x: int, y: int, resolution: int) -> Vector3:
	var step = 1
	var scale = 5.0  # Controls normal strength
	
	# Get safe coordinates for sampling
	var x_minus = max(0, x - step)
	var x_plus = min(resolution - 1, x + step)
	var y_minus = max(0, y - step) 
	var y_plus = min(resolution - 1, y + step)
	
	# Calculate gradient
	var dx = depth_map[y * resolution + x_plus] - depth_map[y * resolution + x_minus]
	var dy = depth_map[y_plus * resolution + x] - depth_map[y_minus * resolution + x]
	
	# Create normal vector (negative gradient + up vector)
	return Vector3(-dx * scale, -dy * scale, 1.0).normalized()

# Apply lighting to a color based on surface normal
func apply_lighting(color: Color, normal: Vector3) -> Color:
	# Convert light direction to 3D
	var light_dir = Vector3(light_direction.x, light_direction.y, 0.7).normalized()
	
	# Calculate diffuse lighting
	var diffuse = max(0.0, normal.dot(light_dir))
	
	# Enhanced lighting model with slight specular highlight
	if enhanced_lighting:
		var specular_power = 8.0
		var specular_factor = 0.2
		
		# Calculate reflection vector
		var reflect_dir = (normal * (2.0 * normal.dot(light_dir)) - light_dir).normalized()
		var view_dir = Vector3(0, 0, 1)  # Viewing directly from above
		
		# Specular component (Phong model)
		var specular = pow(max(0.0, reflect_dir.dot(view_dir)), specular_power) * specular_factor
		
		# Final lighting
		var light_factor = clamp(ambient_light + diffuse * light_intensity + specular, 0.0, 1.0)
		color.r *= light_factor
		color.g *= light_factor
		color.b *= light_factor
	else:
		# Simple diffuse lighting
		var light_factor = clamp(ambient_light + diffuse * light_intensity, 0.0, 1.0)
		color.r *= light_factor
		color.g *= light_factor
		color.b *= light_factor
	
	return color

# Main function to create asteroid texture
func create_asteroid_texture() -> ImageTexture:
	# Check cache first for better performance
	var cache_key = str(seed_value)
	if texture_cache.has(cache_key):
		return texture_cache[cache_key]
	
	# Determine final resolution based on asteroid size and settings
	var final_resolution = resolution
	
	# Create image with appropriate size
	var image = Image.create(final_resolution, final_resolution, true, Image.FORMAT_RGBA8)
	
	# Reset caches
	noise_cache.clear()
	
	# Generate boundary values for asteroid shape
	boundary_values.resize(360)
	
	for degree in range(360):
		var radian = deg_to_rad(degree)
		boundary_values[degree] = boundary_noise(radian)
	
	# Smooth boundary for less jagged appearance
	smooth_boundary_values()
	
	# Scale boundary values appropriately
	var max_boundary = 0.0
	for value in boundary_values:
		max_boundary = max(max_boundary, value)
	
	var scale_factor = 0.9 / max_boundary
	
	# Generate craters
	generate_craters()
	
	# Create depth map for normal mapping
	var depth_map: PackedFloat32Array = PackedFloat32Array()
	depth_map.resize(final_resolution * final_resolution)
	
	# Precalculate normalized coordinates for efficiency
	var nx_lookup: PackedFloat32Array = PackedFloat32Array()
	var ny_lookup: PackedFloat32Array = PackedFloat32Array()
	nx_lookup.resize(final_resolution)
	ny_lookup.resize(final_resolution)
	
	for i in range(final_resolution):
		nx_lookup[i] = float(i) / (final_resolution - 1)
		ny_lookup[i] = float(i) / (final_resolution - 1)
	
	# First pass: Calculate depth map
	for y in range(final_resolution):
		var ny = ny_lookup[y]
		var dy = ny - 0.5
		
		for x in range(final_resolution):
			var nx = nx_lookup[x]
			var dx = nx - 0.5
			
			var distance = sqrt(dx * dx + dy * dy) * 2.0
			var angle = atan2(dy, dx)
			if angle < 0:
				angle += TAU
			
			var degree = int(rad_to_deg(angle)) % 360
			var boundary = boundary_values[degree] * scale_factor
			
			var idx = y * final_resolution + x
			
			if distance > boundary:
				depth_map[idx] = 0.0
				continue
			
			# Calculate combined crater depth
			var crater_depth = 0.0
			for crater in craters:
				crater_depth += calculate_crater_depth(crater, nx, ny)
			
			depth_map[idx] = crater_depth
	
	# Second pass: Apply lighting and create final image
	for y in range(final_resolution):
		var ny = ny_lookup[y]
		var dy = ny - 0.5
		
		for x in range(final_resolution):
			var nx = nx_lookup[x]
			var dx = nx - 0.5
			
			var distance = sqrt(dx * dx + dy * dy) * 2.0
			var angle = atan2(dy, dx)
			if angle < 0:
				angle += TAU
			
			var degree = int(rad_to_deg(angle)) % 360
			var boundary = boundary_values[degree] * scale_factor
			
			if distance > boundary:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			
			# Get spherified coordinates for noise
			var sphere_uv = spherify(nx, ny)
			
			# Generate base noise for texture
			var base_noise = fbm(sphere_uv.x * 4.0, sphere_uv.y * 4.0)
			
			# Get crater depth
			var crater_depth = depth_map[y * final_resolution + x]
			var in_crater = crater_depth < -0.1
			
			# Select color based on noise
			var color_index = int(base_noise * (color_palette.size() - 0.01))
			color_index = clamp(color_index, 0, color_palette.size() - 1)
			var base_color = color_palette[color_index]
			
			# Darken crater interiors
			if in_crater:
				base_color.r *= 0.8
				base_color.g *= 0.8
				base_color.b *= 0.8
			
			# Calculate surface normal for lighting
			var normal = calculate_surface_normal(depth_map, x, y, final_resolution)
			
			# Apply lighting
			var lit_color = apply_lighting(base_color, normal)
			
			# Apply edge darkening
			var edge_intensity = distance / boundary
			var edge_shade = 1.0 - pow(edge_intensity * 1.1, 2)
			
			lit_color.r *= (1.0 - edge_darkening + edge_shade * edge_darkening)
			lit_color.g *= (1.0 - edge_darkening + edge_shade * edge_darkening)
			lit_color.b *= (1.0 - edge_darkening + edge_shade * edge_darkening)
			
			image.set_pixel(x, y, lit_color)
	
	# Create texture from image
	var texture = ImageTexture.create_from_image(image)
	
	# Cache the result
	texture_cache[cache_key] = texture
	
	# Emit signal
	texture_generated.emit(texture)
	
	return texture

# Generate asteroid of a specific size
func generate_asteroid(size: int = ASTEROID_SIZE_MEDIUM) -> void:
	# Clear existing children
	for child in get_children():
		if child is Timer:
			continue
		remove_child(child)
		child.queue_free()
	
	# Initialize with new seed for variety
	if seed_value == 0:
		seed_value = randi()
	
	main_rng.seed = seed_value
	noise_generator.seed = seed_value
	noise_cache.clear()
	
	# Adjust parameters based on size
	var size_factor = float(size) / float(ASTEROID_SIZE_MEDIUM)
	
	# Configure noise generator
	noise_generator.fractal_octaves = 3 if size < ASTEROID_SIZE_LARGE else 4
	
	# Set resolution based on size
	resolution = PIXEL_RESOLUTION
	if size >= ASTEROID_SIZE_LARGE:
		resolution = HIGH_RESOLUTION
	elif size <= ASTEROID_SIZE_SMALL:
		resolution = simplify_small_asteroids if PIXEL_RESOLUTION / 2 else PIXEL_RESOLUTION
	
	# Configure crater count based on size
	crater_count_min = int(max(1, 2 * size_factor))
	crater_count_min = min(crater_count_min, 3)
	crater_count_max = int(max(2, 4 * size_factor))
	
	# Create randomized parameters
	irregularity = main_rng.randf_range(0.35, 0.6)
	irregularity_detail = main_rng.randf_range(1.0, 2.0)
	
	if main_rng.randf() < 0.6:
		elongation = main_rng.randf_range(0.2, 0.4)
	else:
		elongation = main_rng.randf_range(0.6, 0.8)
	
	# Generate the texture
	var asteroid_texture = create_asteroid_texture()
	
	# Create sprite to display the texture
	var asteroid_sprite = Sprite2D.new()
	asteroid_sprite.texture = asteroid_texture
	asteroid_sprite.scale = Vector2(size, size) / resolution
	add_child(asteroid_sprite)

# Static method to clear all texture caches
static func clear_texture_cache() -> void:
	# When static, we can only access other static properties
	texture_cache.clear()
	last_texture_cleanup = Time.get_ticks_msec()
	
	# Note: Since this is static, we can't use get_tree() to find other instances
	# This will be handled separately in non-static context
