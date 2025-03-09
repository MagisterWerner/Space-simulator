# moon_generator.gd
extends RefCounted
class_name MoonGenerator

# Moon type enum (must match moon.gd and planet.gd)
enum MoonType {
	ROCKY,
	ICE,
	LAVA
}

# CHANGED: Separate moon sizes for terran and gaseous planets
const TERRAN_MOON_SIZES: Array = [32, 48]   # Smaller moons for terran planets
const GASEOUS_MOON_SIZES: Array = [128, 160]  # Larger moons for gaseous planetsts
const PIXEL_RESOLUTION: int = 8

const CUBIC_RESOLUTION: int = 8
const BASE_FREQUENCY: float = 8.0
const BASE_AMPLITUDE: float = 0.5

var CRATER_COUNT_MIN: int = 2
var CRATER_COUNT_MAX: int = 5
var CRATER_PIXEL_SIZE_MIN: int = 4
var CRATER_PIXEL_SIZE_MAX: int = 7
var CRATER_SIZE_MIN: float = float(CRATER_PIXEL_SIZE_MIN) / float(PIXEL_RESOLUTION)
var CRATER_SIZE_MAX: float = float(CRATER_PIXEL_SIZE_MAX) / float(PIXEL_RESOLUTION)
var CRATER_DEPTH_MIN: float = 0.25
var CRATER_DEPTH_MAX: float = 0.45
var CRATER_OVERLAP_PREVENTION: float = 1.05

var LIGHT_DIRECTION: Vector2 = Vector2(-0.5, -0.8).normalized()
var AMBIENT_LIGHT: float = 0.65
var LIGHT_INTENSITY: float = 0.35

var cubic_lookup: Array = []
var colors: PackedColorArray
var noise_cache: Dictionary = {}
var craters: Array = []

static var moon_texture_cache: Dictionary = {}

func _init():
	cubic_lookup.resize(CUBIC_RESOLUTION)
	for i in range(CUBIC_RESOLUTION):
		var t = float(i) / (CUBIC_RESOLUTION - 1)
		cubic_lookup[i] = t * t * (3.0 - 2.0 * t)
	
	# Default to rocky moon colors
	colors = get_moon_colors(MoonType.ROCKY)

# Get the appropriate color palette for a moon type
func get_moon_colors(moon_type: int) -> PackedColorArray:
	match moon_type:
		MoonType.ROCKY:
			return PackedColorArray([
				Color(0.69, 0.67, 0.64),
				Color(0.55, 0.53, 0.50),
				Color(0.42, 0.40, 0.38),
				Color(0.35, 0.33, 0.31),
				Color(0.25, 0.23, 0.21)
			])
		MoonType.ICE:
			return PackedColorArray([
				Color(0.98, 0.99, 1.0),   # Almost white
				Color(0.92, 0.97, 1.0),   # Very light blue
				Color(0.85, 0.92, 0.98),  # Light blue
				Color(0.75, 0.85, 0.95),  # Mild blue
				Color(0.60, 0.75, 0.90),  # Medium blue
				Color(0.45, 0.65, 0.85),  # Deeper blue
				Color(0.30, 0.50, 0.75)   # Dark blue
			])
		MoonType.LAVA:
			return PackedColorArray([
				Color(1.0, 0.6, 0.0),     # Bright orange
				Color(0.9, 0.4, 0.05),    # Orange
				Color(0.8, 0.2, 0.05),    # Red-orange
				Color(0.7, 0.1, 0.05),    # Red
				Color(0.55, 0.08, 0.04),  # Dark red
				Color(0.4, 0.06, 0.03),   # Deeper red
				Color(0.25, 0.04, 0.02)   # Almost black-red
			])
		_:
			# Default fallback to rocky
			return PackedColorArray([
				Color(0.69, 0.67, 0.64),
				Color(0.55, 0.53, 0.50),
				Color(0.42, 0.40, 0.38),
				Color(0.35, 0.33, 0.31),
				Color(0.25, 0.23, 0.21)
			])

# Get the parameters for a specific moon type
func get_moon_params(moon_type: int) -> Dictionary:
	match moon_type:
		MoonType.ROCKY:
			return {
				"crater_count_min": 2, 
				"crater_count_max": 5,
				"crater_depth_min": 0.25,
				"crater_depth_max": 0.45,
				"ambient_light": 0.65,
				"light_intensity": 0.35
			}
		MoonType.ICE:
			return {
				"crater_count_min": 1,
				"crater_count_max": 3,
				"crater_depth_min": 0.15,  # Shallower craters
				"crater_depth_max": 0.35,
				"ambient_light": 0.75,     # Brighter ambient light
				"light_intensity": 0.25    # Less harsh shadows
			}
		MoonType.LAVA:
			return {
				"crater_count_min": 3,
				"crater_count_max": 6,
				"crater_depth_min": 0.35,  # Deeper craters
				"crater_depth_max": 0.55,
				"ambient_light": 0.55,     # Darker ambient light
				"light_intensity": 0.45    # More dramatic lighting
			}
		_:
			# Default to rocky parameters if type is invalid
			return {
				"crater_count_min": 2, 
				"crater_count_max": 5,
				"crater_depth_min": 0.25,
				"crater_depth_max": 0.45,
				"ambient_light": 0.65,
				"light_intensity": 0.35
			}

# CHANGED: Added is_gaseous parameter
static func get_moon_texture(seed_value: int, moon_type: int = MoonType.ROCKY, is_gaseous: bool = false) -> Texture2D:
	# Create a unique key for the cache that includes both seed, type and planet category
	var cache_key = seed_value * 100 + moon_type * 10 + (1 if is_gaseous else 0)
	
	if moon_texture_cache.has(cache_key):
		return moon_texture_cache[cache_key]
	
	var generator = new()
	var texture = generator.create_moon_texture(seed_value, moon_type, is_gaseous)
	
	moon_texture_cache[cache_key] = texture
	
	# Clean cache if too large
	if moon_texture_cache.size() > 100:
		var oldest_key = moon_texture_cache.keys()[0]
		moon_texture_cache.erase(oldest_key)
	
	return texture

# CHANGED: Modified to use different size arrays based on is_gaseous
func get_moon_size(seed_value: int, is_gaseous: bool = false) -> int:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# Use appropriate size array based on planet type
	var size_array = GASEOUS_MOON_SIZES if is_gaseous else TERRAN_MOON_SIZES
	var index = rng.randi() % size_array.size()
	
	return size_array[index]

func get_cubic(t: float) -> float:
	var index = int(t * (CUBIC_RESOLUTION - 1))
	index = clamp(index, 0, CUBIC_RESOLUTION - 1)
	return cubic_lookup[index]

func get_random_seed(x: float, y: float, seed_value: int) -> float:
	var key = str(x) + "_" + str(y) + "_" + str(seed_value)
	if noise_cache.has(key):
		return noise_cache[key]
	
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(str(seed_value) + str(x) + str(y))
	var value = rng.randf()
	noise_cache[key] = value
	return value

func noise(x: float, y: float, seed_value: int) -> float:
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

func configure_for_moon_type(moon_type: int) -> void:
	# Get parameters for this moon type
	var params = get_moon_params(moon_type)
	
	# Apply moon type specific parameters
	CRATER_COUNT_MIN = params.crater_count_min
	CRATER_COUNT_MAX = params.crater_count_max
	CRATER_DEPTH_MIN = params.crater_depth_min
	CRATER_DEPTH_MAX = params.crater_depth_max
	AMBIENT_LIGHT = params.ambient_light
	LIGHT_INTENSITY = params.light_intensity
	
	# Set colors for this moon type
	colors = get_moon_colors(moon_type)

func generate_craters(seed_value: int, moon_type: int) -> void:
	var main_rng = RandomNumberGenerator.new()
	main_rng.seed = seed_value

	# Configure parameters for this moon type
	configure_for_moon_type(moon_type)

	craters.clear()
	var crater_count = main_rng.randi_range(CRATER_COUNT_MIN, CRATER_COUNT_MAX)
	var max_attempts = crater_count * 15
	var attempts = 0
	
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
		
		# Apply moon type specific modifications to craters
		match moon_type:
			MoonType.ICE:
				# Ice moons have smoother, more circular craters
				new_crater.noise_amp *= 0.7
				new_crater.elongation *= 0.6
			MoonType.LAVA:
				# Lava moons have more irregular, jagged craters
				new_crater.noise_amp *= 1.3
				new_crater.elongation *= 1.2
		
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
	
	var get_depth = func(px, py):
		if px < 0: px = 0
		elif px >= resolution: px = resolution - 1
		if py < 0: py = 0
		elif py >= resolution: py = resolution - 1
		return depth_map[py * resolution + px]
	
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

# CHANGED: Added is_gaseous parameter to allow for proper sizing
func create_moon_texture(seed_value: int, moon_type: int = MoonType.ROCKY, is_gaseous: bool = false) -> ImageTexture:
	var moon_size = get_moon_size(seed_value, is_gaseous)
	
	var padding = 2
	var padded_size = moon_size + (padding * 2)
	var image = Image.create(padded_size, padded_size, true, Image.FORMAT_RGBA8)
	
	noise_cache.clear()
	
	# Configure for the specified moon type
	configure_for_moon_type(moon_type)
	
	# Generate craters with type-specific parameters
	generate_craters(seed_value, moon_type)
	
	var sphere_data = []
	sphere_data.resize(padded_size * padded_size)
	var nx_values = []
	var ny_values = []
	
	nx_values.resize(padded_size)
	ny_values.resize(padded_size)
	
	for i in range(padded_size):
		nx_values[i] = (float(i) - padding) / (moon_size - 1)
		ny_values[i] = (float(i) - padding) / (moon_size - 1)
	
	for y in range(padded_size):
		var ny = ny_values[y]
		var dy = ny - 0.5
		
		for x in range(padded_size):
			var nx = nx_values[x]
			var dx = nx - 0.5
			var d_circle = sqrt(dx * dx + dy * dy) * 2.0
			
			var idx = y * padded_size + x
			if d_circle > 1.0:
				sphere_data[idx] = null
			else:
				sphere_data[idx] = {
					"uv": spherify(nx, ny),
					"d_circle": d_circle,
					"nx": nx,
					"ny": ny
				}
	
	var depth_map = []
	depth_map.resize(padded_size * padded_size)
	
	for y in range(padded_size):
		for x in range(padded_size):
			var idx = y * padded_size + x
			var data = sphere_data[idx]
			
			if data == null:
				depth_map[idx] = 0.0
				continue
			
			var crater_depth = 0.0
			for crater in craters:
				crater_depth += calculate_crater_depth(crater, data.nx, data.ny)
			
			depth_map[idx] = crater_depth
	
	var color_size = colors.size() - 1
	
	for y in range(padded_size):
		for x in range(padded_size):
			var idx = y * padded_size + x
			var data = sphere_data[idx]
			
			if data == null:
				# PIXEL-PERFECT EDGE: Set fully transparent outside the circle
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			
			var sphere_uv = data.uv
			var d_circle = data.d_circle
			
			var base_noise = fbm(sphere_uv.x, sphere_uv.y, seed_value)
			
			var crater_depth = depth_map[idx]
			var in_crater = crater_depth < -0.1
			
			# Apply moon type specific noise adjustments
			match moon_type:
				MoonType.ICE:
					# Ice moons have smoother surfaces
					base_noise = pow(base_noise, 0.7)  # Favor brighter values
					# Add slight shimmer to ice
					base_noise += noise(sphere_uv.x * 20, sphere_uv.y * 20, seed_value + 123) * 0.05
					
				MoonType.LAVA:
					# Lava moons have more contrast and "hotspots"
					base_noise = pow(base_noise, 1.3)  # Increase contrast
					
					# Create potential "hotspots" or lava flows
					var lava_noise = noise(sphere_uv.x * 8, sphere_uv.y * 8, seed_value + 789)
					if lava_noise > 0.7 and not in_crater:
						# Make some areas brighter to simulate glowing spots
						base_noise = min(1.0, base_noise + 0.3)
			
			# Adjust crater depth impact based on moon type
			if in_crater:
				match moon_type:
					MoonType.ROCKY:
						base_noise = max(0.0, base_noise - abs(crater_depth) * 0.5)
					MoonType.ICE:
						# Ice crater floors are brighter (exposed ice)
						base_noise = max(0.2, base_noise - abs(crater_depth) * 0.3)
					MoonType.LAVA:
						# Lava crater floors are darker (cooling areas)
						base_noise = max(0.0, base_noise - abs(crater_depth) * 0.7)
			
			var color_index = int(base_noise * color_size)
			color_index = clamp(color_index, 0, color_size)
			var base_color = colors[color_index]
			
			# Apply special effects based on moon type
			match moon_type:
				MoonType.ICE:
					# Add subtle blue glow to edges
					if d_circle > 0.8:
						base_color.b = min(1.0, base_color.b + 0.1)
				
				MoonType.LAVA:
					# Add orange/red glow to some areas
					var heat_noise = noise(sphere_uv.x * 12, sphere_uv.y * 12, seed_value + 456)
					if heat_noise > 0.7 and not in_crater:
						base_color.r = min(1.0, base_color.r + 0.15)
						base_color.g = min(1.0, base_color.g + 0.05)
			
			var normal = calculate_normal(depth_map, x, y, padded_size)
			var lit_color = apply_lighting(base_color, normal)
			
			var edge_factor = 1.0 - pow(d_circle, 2) * 0.2
			
			# PIXEL-PERFECT EDGE: Set alpha to 1.0 for all visible pixels
			# No edge anti-aliasing, full opacity for all pixels inside the circle
			var final_color = Color(
				lit_color.r * edge_factor,
				lit_color.g * edge_factor,
				lit_color.b * edge_factor,
				1.0  # Always fully opaque
			)
			
			image.set_pixel(x, y, final_color)
	
	var final_image = Image.create(moon_size, moon_size, true, Image.FORMAT_RGBA8)
	for y in range(moon_size):
		for x in range(moon_size):
			final_image.set_pixel(x, y, image.get_pixel(x + padding, y + padding))
	
	return ImageTexture.create_from_image(final_image)
