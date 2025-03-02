# moon_generator.gd - Procedural moon generation system
extends RefCounted

# Moon generation constants and configuration
# Modified moon sizes to be specific fixed values
const MOON_SIZES: Array = [24, 32, 40, 48, 56]  # Fixed pixel sizes for moons
const PIXEL_RESOLUTION: int = 64  # Base resolution for textures (will be used based on moon size)

# Optimized noise generation parameters
const CUBIC_RESOLUTION: int = 512
const BASE_FREQUENCY: float = 8.0
const BASE_AMPLITUDE: float = 0.5

# Crater parameters
var CRATER_COUNT_MIN: int = 2
var CRATER_COUNT_MAX: int = 5
var CRATER_PIXEL_SIZE_MIN: int = 4
var CRATER_PIXEL_SIZE_MAX: int = 7
var CRATER_SIZE_MIN: float = float(CRATER_PIXEL_SIZE_MIN) / float(PIXEL_RESOLUTION)
var CRATER_SIZE_MAX: float = float(CRATER_PIXEL_SIZE_MAX) / float(PIXEL_RESOLUTION)
var CRATER_DEPTH_MIN: float = 0.25
var CRATER_DEPTH_MAX: float = 0.45
var CRATER_OVERLAP_PREVENTION: float = 1.05

# Lighting parameters
var LIGHT_DIRECTION: Vector2 = Vector2(-0.5, -0.8).normalized()
var AMBIENT_LIGHT: float = 0.65
var LIGHT_INTENSITY: float = 0.35

# Precomputed lookup tables and caches
var cubic_lookup: Array = []
var colors: PackedColorArray
var noise_cache: Dictionary = {}
var craters: Array = []

# Texture cache for performance
static var moon_texture_cache: Dictionary = {}

# Initialize the generator
func _init():
	# Initialize lookup table
	cubic_lookup.resize(CUBIC_RESOLUTION)
	for i in range(CUBIC_RESOLUTION):
		var t = float(i) / (CUBIC_RESOLUTION - 1)
		cubic_lookup[i] = t * t * (3.0 - 2.0 * t)
	
	# Lunar surface color palette
	colors = PackedColorArray([
		Color(0.69, 0.67, 0.64),  # Light gray-beige of lunar highlands
		Color(0.55, 0.53, 0.50),  # Medium gray of maria (lunar plains)
		Color(0.42, 0.40, 0.38),  # Darker gray of older lunar surfaces
		Color(0.35, 0.33, 0.31),  # Deep gray of shadowed crater regions
		Color(0.25, 0.23, 0.21)   # Darkest gray of ancient, compressed lunar terrain
	])

# Get a cached texture or generate a new one
static func get_moon_texture(seed_value: int) -> Texture2D:
	if moon_texture_cache.has(seed_value):
		return moon_texture_cache[seed_value]
	
	var generator = new()
	var texture = generator.create_moon_texture(seed_value)
	
	# Cache the texture
	moon_texture_cache[seed_value] = texture
	
	# Limit cache size to prevent memory issues
	if moon_texture_cache.size() > 100:
		var oldest_key = moon_texture_cache.keys()[0]
		moon_texture_cache.erase(oldest_key)
	
	return texture

# Get moon size based on seed - returns one of the fixed moon sizes
func get_moon_size(seed_value: int) -> int:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# Return one of the predefined moon sizes
	var index = rng.randi() % MOON_SIZES.size()
	return MOON_SIZES[index]

func get_cubic(t: float) -> float:
	# Fast cubic interpolation using precomputed lookup
	var index = int(t * (CUBIC_RESOLUTION - 1))
	index = clamp(index, 0, CUBIC_RESOLUTION - 1)
	return cubic_lookup[index]

func get_random_seed(x: float, y: float, seed_value: int) -> float:
	# Cached random seed generation
	var key = str(x) + "_" + str(y) + "_" + str(seed_value)
	if noise_cache.has(key):
		return noise_cache[key]
	
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(str(seed_value) + str(x) + str(y))
	var value = rng.randf()
	noise_cache[key] = value
	return value

func noise(x: float, y: float, seed_value: int) -> float:
	# Optimized noise generation
	var ix = floor(x)
	var iy = floor(y)
	var fx = x - ix
	var fy = y - iy
	
	var cubic_x = get_cubic(fx)
	var cubic_y = get_cubic(fy)
	
	var a = get_random_seed(ix, iy, seed_value)
	var b = get_random_seed(ix + 1.0, iy, seed_value)
	var c = get_random_seed(ix, iy + 1.0, seed_value)
	var d = get_random_seed(ix + 1.0, iy + 1.0, seed_value)
	
	return lerp(
		lerp(a, b, cubic_x),
		lerp(c, d, cubic_x),
		cubic_y
	)

func fbm(x: float, y: float, seed_value: int) -> float:
	# Optimized fractal Brownian motion with fewer octaves
	var value = 0.0
	var amplitude = BASE_AMPLITUDE
	var frequency = BASE_FREQUENCY
	
	value += noise(x * frequency, y * frequency, seed_value) * amplitude
	
	frequency *= 2.0
	amplitude *= 0.5
	value += noise(x * frequency, y * frequency, seed_value) * amplitude
	
	frequency *= 2.0
	amplitude *= 0.5
	value += noise(x * frequency, y * frequency, seed_value) * amplitude
	
	return value

func spherify(x: float, y: float) -> Vector2:
	# Efficient spherification
	var centered_x = x * 2.0 - 1.0
	var centered_y = y * 2.0 - 1.0
	
	var length_squared = centered_x * centered_x + centered_y * centered_y
	
	if length_squared >= 1.0:
		return Vector2(x, y)
	
	var z = sqrt(1.0 - length_squared)
	var z_plus_one = z + 1.0
	
	return Vector2(
		(centered_x / z_plus_one + 1.0) * 0.5,
		(centered_y / z_plus_one + 1.0) * 0.5
	)

func is_crater_overlapping(new_crater: Dictionary) -> bool:
	for existing_crater in craters:
		var center_dx = new_crater.center_x - existing_crater.center_x
		var center_dy = new_crater.center_y - existing_crater.center_y
		var center_distance_sq = center_dx * center_dx + center_dy * center_dy
		
		var min_distance = (new_crater.size + existing_crater.size) * CRATER_OVERLAP_PREVENTION
		var min_distance_sq = min_distance * min_distance
		
		if center_distance_sq < min_distance_sq:
			return true
	
	return false

func generate_craters(seed_value: int) -> void:
	var main_rng = RandomNumberGenerator.new()
	main_rng.seed = seed_value

	craters.clear()
	var crater_count = main_rng.randi_range(CRATER_COUNT_MIN, CRATER_COUNT_MAX)
	var max_attempts = crater_count * 15
	var attempts = 0
	
	# Pre-generate crater sizes for better performance
	var available_sizes = []
	available_sizes.resize(CRATER_PIXEL_SIZE_MAX - CRATER_PIXEL_SIZE_MIN + 1)
	for i in range(CRATER_PIXEL_SIZE_MIN, CRATER_PIXEL_SIZE_MAX + 1):
		available_sizes[i - CRATER_PIXEL_SIZE_MIN] = float(i) / float(PIXEL_RESOLUTION)
	
	while craters.size() < crater_count and attempts < max_attempts:
		var angle = main_rng.randf() * TAU
		var radius = main_rng.randf_range(0.1, 0.9)
		
		var center_x = 0.5 + cos(angle) * radius * 0.5
		var center_y = 0.5 + sin(angle) * radius * 0.5
		
		var size_index = main_rng.randi() % available_sizes.size()
		var size = available_sizes[size_index]
		
		var new_crater = {
			"center_x": center_x,
			"center_y": center_y,
			"size": size,
			"depth": main_rng.randf_range(CRATER_DEPTH_MIN, CRATER_DEPTH_MAX),
			"noise_freq": main_rng.randf_range(2.0, 4.0),
			"noise_amp": main_rng.randf_range(0.1, 0.25),
			"angle": main_rng.randf() * TAU,
			"elongation": main_rng.randf_range(0.0, 0.2)
		}
		
		if not is_crater_overlapping(new_crater):
			craters.append(new_crater)
		
		attempts += 1

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
	
	# Simplified shape factor calculation
	var noise_x = cos(angle) * crater.noise_freq
	var noise_y = sin(angle) * crater.noise_freq
	var shape_noise = noise(noise_x, noise_y, 12345) * crater.noise_amp
	var shape_factor = 1.0 + shape_noise * distance_normalized
	
	if crater.elongation > 0.05:
		var elongation_angle = crater.angle
		var dx_angle = cos(angle - elongation_angle)
		shape_factor *= (1.0 + dx_angle * crater.elongation)
	
	if distance_normalized > shape_factor:
		return 0.0
	
	var shaped_distance = distance_normalized / shape_factor
	
	# Optimized depth profile calculation
	var depth_factor = 0.0
	
	if shaped_distance < 0.2:
		depth_factor = -crater.depth * (0.85 + pow(shaped_distance / 0.2, 0.7) * 0.15)
	elif shaped_distance < 0.85:
		var wall_factor = (shaped_distance - 0.2) / 0.65
		depth_factor = -crater.depth * (1.0 - pow(wall_factor, 0.9)) * 0.85
	else:
		var rim_factor = (shaped_distance - 0.85) / 0.15
		depth_factor = crater.depth * 0.04 * (1.0 - rim_factor) * (1.0 - rim_factor)
	
	return depth_factor

func calculate_normal(depth_map: Array, x: int, y: int, resolution: int) -> Vector3:
	var step = 1
	var scale = 4.0
	
	# Fast boundary-safe depth lookup
	var get_depth = func(px, py):
		if px < 0: px = 0
		elif px >= resolution: px = resolution - 1
		if py < 0: py = 0
		elif py >= resolution: py = resolution - 1
		return depth_map[py * resolution + px]
	
	# Central differences for normal calculation
	var dx = get_depth.call(x + step, y) - get_depth.call(x - step, y)
	var dy = get_depth.call(x, y + step) - get_depth.call(x, y - step)
	
	return Vector3(-dx * scale, -dy * scale, 1.0).normalized()

func apply_lighting(color: Color, normal: Vector3) -> Color:
	var light_dir = Vector3(LIGHT_DIRECTION.x, LIGHT_DIRECTION.y, 0.7).normalized()
	var diffuse = max(0.0, normal.dot(light_dir))
	var light_factor = AMBIENT_LIGHT + diffuse * LIGHT_INTENSITY
	
	return Color(
		color.r * light_factor,
		color.g * light_factor,
		color.b * light_factor,
		color.a
	)

func create_moon_texture(seed_value: int) -> ImageTexture:
	# Get the moon size based on seed
	var moon_size = get_moon_size(seed_value)
	
	# Create image at the exact pixel size
	var final_resolution = moon_size
	var image = Image.create(final_resolution, final_resolution, true, Image.FORMAT_RGBA8)
	
	noise_cache.clear()
	generate_craters(seed_value)
	
	# Pre-calculate pixel coordinates and sphere data for better performance
	var sphere_data = []
	sphere_data.resize(final_resolution * final_resolution)
	var nx_values = []
	var ny_values = []
	
	nx_values.resize(final_resolution)
	ny_values.resize(final_resolution)
	
	for i in range(final_resolution):
		nx_values[i] = float(i) / (final_resolution - 1)
		ny_values[i] = float(i) / (final_resolution - 1)
	
	for y in range(final_resolution):
		var ny = ny_values[y]
		var dy = ny - 0.5
		
		for x in range(final_resolution):
			var nx = nx_values[x]
			var dx = nx - 0.5
			var d_circle = sqrt(dx * dx + dy * dy) * 2.0
			
			var idx = y * final_resolution + x
			if d_circle > 1.0:
				sphere_data[idx] = null
			else:
				sphere_data[idx] = {
					"uv": spherify(nx, ny),
					"d_circle": d_circle,
					"nx": nx,
					"ny": ny
				}
	
	# Calculate crater depth map
	var depth_map = []
	depth_map.resize(final_resolution * final_resolution)
	
	for y in range(final_resolution):
		for x in range(final_resolution):
			var idx = y * final_resolution + x
			var data = sphere_data[idx]
			
			if data == null:
				depth_map[idx] = 0.0
				continue
			
			var crater_depth = 0.0
			for crater in craters:
				crater_depth += calculate_crater_depth(crater, data.nx, data.ny)
			
			depth_map[idx] = crater_depth
	
	# Generate final image with lighting
	var color_size = colors.size() - 1
	
	for y in range(final_resolution):
		for x in range(final_resolution):
			var idx = y * final_resolution + x
			var data = sphere_data[idx]
			
			if data == null:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			
			# Generate base texture
			var sphere_uv = data.uv
			var d_circle = data.d_circle
			
			var base_noise = fbm(sphere_uv.x, sphere_uv.y, seed_value)
			
			# Get crater depth and adjust noise
			var crater_depth = depth_map[idx]
			var in_crater = crater_depth < -0.1
			
			if in_crater:
				base_noise = max(0.0, base_noise - abs(crater_depth) * 0.5)
			
			# Select color and apply lighting
			var color_index = int(base_noise * color_size)
			color_index = clamp(color_index, 0, color_size)
			var base_color = colors[color_index]
			
			# Calculate normal and apply lighting
			var normal = calculate_normal(depth_map, x, y, final_resolution)
			var lit_color = apply_lighting(base_color, normal)
			
			# Add subtle edge shading
			var edge_factor = 1.0 - pow(d_circle, 2) * 0.2
			var final_color = Color(
				lit_color.r * edge_factor,
				lit_color.g * edge_factor,
				lit_color.b * edge_factor,
				1.0
			)
			
			image.set_pixel(x, y, final_color)
	
	return ImageTexture.create_from_image(image)
