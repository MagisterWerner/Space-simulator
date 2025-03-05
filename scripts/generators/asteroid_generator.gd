# asteroid_generator.gd
extends Node2D

const ASTEROID_SIZE_SMALL: int = 16
const ASTEROID_SIZE_MEDIUM: int = 32
const ASTEROID_SIZE_LARGE: int = 64

const CUBIC_RESOLUTION: int = 512
const BASE_FREQUENCY: float = 8.0
const BASE_AMPLITUDE: float = 0.5
const PIXEL_RESOLUTION: int = 64

var IRREGULARITY: float = 0.38
var IRREGULARITY_DETAIL: float = 1.4
var ELONGATION: float = 0.75
var ELONGATION_ANGLE: float = 0.0
var BOUNDARY_SMOOTHING: int = 8
var ASYMMETRY_STRENGTH: float = 0.5

var CRATER_COUNT_MIN: int = 1
var CRATER_COUNT_MAX: int = 3
var CRATER_PIXEL_SIZE_MIN: int = 3
var CRATER_PIXEL_SIZE_MAX: int = 5
var CRATER_SIZE_MIN: float = float(CRATER_PIXEL_SIZE_MIN) / float(PIXEL_RESOLUTION)
var CRATER_SIZE_MAX: float = float(CRATER_PIXEL_SIZE_MAX) / float(PIXEL_RESOLUTION)
var CRATER_DEPTH_MIN: float = 0.25
var CRATER_DEPTH_MAX: float = 0.5
var CRATER_OVERLAP_PREVENTION: float = 1.1
var CRATER_IRREGULARITY: float = 0.3
var CRATER_RIM_WIDTH: float = 0.15

var LIGHT_DIRECTION: Vector2 = Vector2(-0.5, -0.8).normalized()
var AMBIENT_LIGHT: float = 0.6
var LIGHT_INTENSITY: float = 0.4

var cubic_lookup: Array = []
var colors: PackedColorArray
var boundary_values: Array = []
var sin_table: Array = []
var cos_table: Array = []

var main_rng: RandomNumberGenerator
var seed_value: int = 0
var noise_cache: Dictionary = {}
var craters: Array = []

func _init():
	main_rng = RandomNumberGenerator.new()
	
	cubic_lookup.resize(CUBIC_RESOLUTION)
	for i in range(CUBIC_RESOLUTION):
		var t = float(i) / (CUBIC_RESOLUTION - 1)
		cubic_lookup[i] = t * t * (3.0 - 2.0 * t)
	
	sin_table.resize(360)
	cos_table.resize(360)
	for i in range(360):
		var angle = deg_to_rad(i)
		sin_table[i] = sin(angle)
		cos_table[i] = cos(angle)
	
	colors = PackedColorArray([
		Color(0.25, 0.24, 0.24),
		Color(0.22, 0.21, 0.21),
		Color(0.20, 0.19, 0.19),
		Color(0.18, 0.17, 0.17),
		Color(0.16, 0.15, 0.15),
		Color(0.14, 0.13, 0.13),
		Color(0.12, 0.11, 0.11),
		Color(0.10, 0.09, 0.09),
	])

func get_cubic(t: float) -> float:
	var index = int(t * (CUBIC_RESOLUTION - 1))
	index = clamp(index, 0, CUBIC_RESOLUTION - 1)
	return cubic_lookup[index]

func get_random_seed(x: float, y: float) -> float:
	var key = str(x) + "_" + str(y)
	if noise_cache.has(key):
		return noise_cache[key]
	
	main_rng.seed = hash(str(seed_value) + str(x) + str(y))
	var value = main_rng.randf()
	noise_cache[key] = value
	return value

func noise(x: float, y: float) -> float:
	var ix = floor(x)
	var iy = floor(y)
	var fx = x - ix
	var fy = y - iy
	
	var cubic_x = get_cubic(fx)
	var cubic_y = get_cubic(fy)
	
	var a = get_random_seed(ix, iy)
	var b = get_random_seed(ix + 1.0, iy)
	var c = get_random_seed(ix, iy + 1.0)
	var d = get_random_seed(ix + 1.0, iy + 1.0)
	
	return lerp(
		lerp(a, b, cubic_x),
		lerp(c, d, cubic_x),
		cubic_y
	)

func fbm(x: float, y: float) -> float:
	var value = 0.0
	var amplitude = BASE_AMPLITUDE
	var frequency = BASE_FREQUENCY
	
	value += noise(x * frequency, y * frequency) * amplitude
	
	frequency *= 2.0
	amplitude *= 0.5
	value += noise(x * frequency, y * frequency) * amplitude
	
	frequency *= 2.0
	amplitude *= 0.5
	value += noise(x * frequency, y * frequency) * amplitude
	
	return value

func boundary_noise(angle: float) -> float:
	var x = cos(angle) * IRREGULARITY_DETAIL
	var y = sin(angle) * IRREGULARITY_DETAIL
	
	var boundary_value = noise(x, y) * IRREGULARITY
	boundary_value += noise(x * 2.0, y * 2.0) * (IRREGULARITY * 0.4)
	boundary_value += noise(x * 4.0, y * 4.0) * (IRREGULARITY * 0.15)
	
	var large_scale_variation = sin(angle * 1.5) * cos(angle * 0.5) * IRREGULARITY * ASYMMETRY_STRENGTH
	large_scale_variation += sin(angle * 2.3) * cos(angle * 1.7) * IRREGULARITY * ASYMMETRY_STRENGTH * 0.7
	boundary_value += large_scale_variation
	
	return 1.0 - IRREGULARITY + boundary_value

func smooth_boundary_values() -> void:
	var smoothed = []
	smoothed.resize(boundary_values.size())
	
	var window_size = BOUNDARY_SMOOTHING
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
		
		for i in range(size):
			boundary_values[i] = smoothed[i]

func apply_elongation(point: Vector2) -> Vector2:
	var angle = ELONGATION_ANGLE
	
	var rotated_x = point.x * cos(-angle) - point.y * sin(-angle)
	var rotated_y = point.x * sin(-angle) + point.y * cos(-angle)
	
	var stretch_x = 1.0 + ELONGATION
	var stretch_y = 1.0 - ELONGATION * 0.6
	
	if point.x > 0:
		stretch_x *= (1.0 + main_rng.randf_range(-0.1, 0.2) * ELONGATION)
	if point.y > 0:
		stretch_y *= (1.0 + main_rng.randf_range(-0.1, 0.2) * ELONGATION)
		
	rotated_x *= stretch_x
	rotated_y *= stretch_y
	
	var radius = sqrt(rotated_x * rotated_x + rotated_y * rotated_y)
	var distortion_angle = atan2(rotated_y, rotated_x)
	
	var angular_distortion = sin(distortion_angle * 3.0) * 0.15 * ELONGATION
	var x_distortion = cos(angular_distortion * PI) * radius * 0.15
	var y_distortion = sin(angular_distortion * PI) * radius * 0.15
	
	rotated_x += x_distortion
	rotated_y += y_distortion
	
	var result_x = rotated_x * cos(angle) - rotated_y * sin(angle)
	var result_y = rotated_x * sin(angle) + rotated_y * cos(angle)
	
	return Vector2(result_x, result_y)

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

func generate_craters() -> void:
	craters.clear()
	var crater_count = main_rng.randi_range(CRATER_COUNT_MIN, CRATER_COUNT_MAX)
	var max_attempts = crater_count * 20
	var attempts = 0
	
	var available_sizes = []
	for size in range(CRATER_PIXEL_SIZE_MIN, CRATER_PIXEL_SIZE_MAX + 1):
		available_sizes.append(float(size) / float(PIXEL_RESOLUTION))
	
	while craters.size() < crater_count and attempts < max_attempts:
		var angle = main_rng.randf_range(0, TAU)
		var radius = main_rng.randf_range(0.2, 0.8)
		
		var center_x = 0.5 + cos(angle) * radius * 0.5
		var center_y = 0.5 + sin(angle) * radius * 0.5
		
		var size_index = main_rng.randi() % available_sizes.size()
		var size = available_sizes[size_index]
		
		var depth = main_rng.randf_range(CRATER_DEPTH_MIN, CRATER_DEPTH_MAX)
		
		var new_crater = {
			"center_x": center_x,
			"center_y": center_y,
			"size": size,
			"depth": depth,
			"noise_freq": main_rng.randf_range(2.0, 4.0),
			"noise_amp": main_rng.randf_range(0.1, CRATER_IRREGULARITY),
			"angle": main_rng.randf_range(0, TAU),
			"elongation": main_rng.randf_range(0.0, 0.2),
			"floor_texture": main_rng.randf_range(0.8, 1.2),
			"floor_noise_freq": main_rng.randf_range(3.0, 5.0),
		}
		
		if not is_crater_overlapping(new_crater):
			craters.append(new_crater)
		
		attempts += 1
	
	if craters.size() > CRATER_COUNT_MAX:
		craters.resize(CRATER_COUNT_MAX)

func get_crater_shape_factor(crater: Dictionary, angle: float, distance_normalized: float) -> float:
	var noise_x = cos(angle) * crater.noise_freq
	var noise_y = sin(angle) * crater.noise_freq
	
	var shape_noise = noise(noise_x, noise_y) * crater.noise_amp
	
	if crater.size > CRATER_SIZE_MAX * 0.7:
		shape_noise += noise(noise_x * 2.0, noise_y * 2.0) * (crater.noise_amp * 0.5)
	
	var shape_factor = 1.0 + shape_noise * distance_normalized
	
	if crater.elongation > 0.05:
		var elongation_angle = crater.angle
		var dx = cos(angle - elongation_angle)
		shape_factor *= (1.0 + dx * crater.elongation)
	
	return shape_factor

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

func calculate_surface_normal(depth_map: Array, x: int, y: int, resolution: int) -> Vector3:
	var step = 1
	var scale = 5.0
	
	var get_safe_depth = func(px, py):
		if px < 0 or px >= resolution or py < 0 or py >= resolution:
			return 0.0
		return depth_map[py * resolution + px]
	
	var dx = get_safe_depth.call(x + step, y) - get_safe_depth.call(x - step, y)
	var dy = get_safe_depth.call(x, y + step) - get_safe_depth.call(x, y - step)
	
	return Vector3(-dx * scale, -dy * scale, 1.0).normalized()

func apply_lighting(color: Color, normal: Vector3) -> Color:
	var light_dir = Vector3(LIGHT_DIRECTION.x, LIGHT_DIRECTION.y, 0.7).normalized()
	var diffuse = max(0.0, normal.dot(light_dir))
	var light_factor = clamp(AMBIENT_LIGHT + diffuse * LIGHT_INTENSITY, 0.0, 1.0)
	
	return Color(
		color.r * light_factor,
		color.g * light_factor,
		color.b * light_factor,
		color.a
	)

func create_asteroid_texture() -> ImageTexture:
	var final_resolution = PIXEL_RESOLUTION
	var image = Image.create(final_resolution, final_resolution, true, Image.FORMAT_RGBA8)
	
	noise_cache.clear()
	boundary_values.resize(360)
	
	for degree in range(360):
		var radian = deg_to_rad(degree)
		boundary_values[degree] = boundary_noise(radian)
	
	smooth_boundary_values()
	
	var max_boundary = 0.0
	for value in boundary_values:
		max_boundary = max(max_boundary, value)
	
	var scale_factor = 0.9 / max_boundary
	generate_craters()
	
	var depth_map = []
	depth_map.resize(final_resolution * final_resolution)
	
	var nx_lookup = []
	var ny_lookup = []
	nx_lookup.resize(final_resolution)
	ny_lookup.resize(final_resolution)
	
	for i in range(final_resolution):
		nx_lookup[i] = float(i) / (final_resolution - 1)
		ny_lookup[i] = float(i) / (final_resolution - 1)
	
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
				depth_map[y * final_resolution + x] = 0.0
				continue
			
			var crater_depth = 0.0
			for crater in craters:
				crater_depth += calculate_crater_depth(crater, nx, ny)
			
			depth_map[y * final_resolution + x] = crater_depth
	
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
			
			var sphere_uv = spherify(nx, ny)
			var base_noise = fbm(sphere_uv.x, sphere_uv.y)
			var crater_depth = depth_map[y * final_resolution + x]
			var in_crater = crater_depth < -0.1
			
			var color_index = int(base_noise * (colors.size() * 0.8))
			color_index = clamp(color_index, 0, colors.size() - 2)
			var base_color = colors[color_index]
			
			if in_crater:
				var crater_shade = 0.8
				base_color = Color(
					base_color.r * crater_shade,
					base_color.g * crater_shade,
					base_color.b * crater_shade,
					1.0
				)
			
			var normal = calculate_surface_normal(depth_map, x, y, final_resolution)
			var lit_color = apply_lighting(base_color, normal)
			
			var edge_intensity = distance / boundary
			var edge_shade = 1.0 - pow(edge_intensity * 1.1, 2)
			var final_color = Color(
				lit_color.r * (0.85 + edge_shade * 0.15),
				lit_color.g * (0.85 + edge_shade * 0.15),
				lit_color.b * (0.85 + edge_shade * 0.15),
				1.0
			)
			
			image.set_pixel(x, y, final_color)
	
	return ImageTexture.create_from_image(image)

func set_random_shape_params():
	IRREGULARITY = main_rng.randf_range(0.35, 0.6)
	IRREGULARITY_DETAIL = main_rng.randf_range(1.0, 2.0)
	
	if main_rng.randf() < 0.6:
		ELONGATION = main_rng.randf_range(0.2, 0.4)
	else:
		ELONGATION = main_rng.randf_range(0.6, 0.8)
	
	ELONGATION_ANGLE = main_rng.randf_range(0, TAU)
	BOUNDARY_SMOOTHING = main_rng.randi_range(4, 7)
	ASYMMETRY_STRENGTH = main_rng.randf_range(0.4, 0.7)

func generate_asteroid(size: int) -> void:
	for child in get_children():
		child.queue_free()
	
	seed_value = randi()
	noise_cache.clear()
	main_rng.seed = seed_value
	
	set_random_shape_params()
	
	var size_factor = float(size) / float(ASTEROID_SIZE_MEDIUM)
	CRATER_COUNT_MIN = int(max(1, 2 * size_factor))
	CRATER_COUNT_MIN = min(CRATER_COUNT_MIN, 3)
	CRATER_COUNT_MAX = 5
	
	if size == ASTEROID_SIZE_SMALL:
		CRATER_PIXEL_SIZE_MIN = 4
		CRATER_PIXEL_SIZE_MAX = 4
	elif size == ASTEROID_SIZE_MEDIUM:
		CRATER_PIXEL_SIZE_MIN = 4
		CRATER_PIXEL_SIZE_MAX = 4
	else:
		CRATER_PIXEL_SIZE_MIN = 4
		CRATER_PIXEL_SIZE_MAX = 5
	
	CRATER_SIZE_MIN = float(CRATER_PIXEL_SIZE_MIN) / float(PIXEL_RESOLUTION)
	CRATER_SIZE_MAX = float(CRATER_PIXEL_SIZE_MAX) / float(PIXEL_RESOLUTION)
	
	CRATER_IRREGULARITY = clamp(0.2 * size_factor, 0.1, 0.3)
	
	var asteroid_texture = create_asteroid_texture()
	
	var asteroid_texture_rect = TextureRect.new()
	asteroid_texture_rect.texture = asteroid_texture
	asteroid_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	asteroid_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	asteroid_texture_rect.custom_minimum_size = Vector2(size, size)
	
	var center_container = CenterContainer.new()
	center_container.custom_minimum_size = Vector2(size, size)
	center_container.add_child(asteroid_texture_rect)
	
	add_child(center_container)

func _ready():
	generate_asteroid(ASTEROID_SIZE_MEDIUM)

func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				generate_asteroid(ASTEROID_SIZE_SMALL)
			KEY_2:
				generate_asteroid(ASTEROID_SIZE_MEDIUM)
			KEY_3:
				generate_asteroid(ASTEROID_SIZE_LARGE)
			KEY_SPACE:
				var sizes = [ASTEROID_SIZE_SMALL, ASTEROID_SIZE_MEDIUM, ASTEROID_SIZE_LARGE]
				var random_size = sizes[main_rng.randi() % sizes.size()]
				generate_asteroid(random_size)
