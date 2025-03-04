# planet_generator.gd
extends RefCounted
class_name PlanetGenerator

enum PlanetTheme {
	ARID,
	ICE,
	LAVA,
	LUSH,
	DESERT,
	ALPINE,
	OCEAN
}

const PLANET_SIZE_LARGE: int = 256
const PLANET_RADIUS: float = 128.0

const TERRAIN_OCTAVES: int = 4
const COLOR_VARIATION: float = 1.5

static var planet_texture_cache: Dictionary = {}

var cubic_lookup: Array = []
var noise_cache: Dictionary = {}
const CUBIC_RESOLUTION: int = 512

func _init():
	cubic_lookup.resize(CUBIC_RESOLUTION)
	for i in range(CUBIC_RESOLUTION):
		var t = float(i) / (CUBIC_RESOLUTION - 1)
		cubic_lookup[i] = t * t * (3.0 - 2.0 * t)

static func get_planet_texture(seed_value: int) -> Array:
	if planet_texture_cache.has(seed_value):
		return planet_texture_cache[seed_value]
	
	var generator = new()
	var textures = generator.create_planet_texture(seed_value)
	
	planet_texture_cache[seed_value] = textures
	
	if planet_texture_cache.size() > 50:
		var oldest_key = planet_texture_cache.keys()[0]
		planet_texture_cache.erase(oldest_key)
	
	return textures

func get_planet_size(_seed_value: int) -> int:
	return PLANET_SIZE_LARGE

func get_planet_theme(seed_value: int) -> int:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng.randi() % PlanetTheme.size()

func get_random_seed(x: float, y: float, seed_value: int) -> float:
	var key = str(x) + "_" + str(y) + "_" + str(seed_value)
	if noise_cache.has(key):
		return noise_cache[key]
	
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(str(seed_value) + str(x) + str(y))
	var value = rng.randf()
	
	noise_cache[key] = value
	return value

func get_cubic(t: float) -> float:
	var index = int(t * (CUBIC_RESOLUTION - 1))
	index = clamp(index, 0, CUBIC_RESOLUTION - 1)
	return cubic_lookup[index]

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

func fbm(x: float, y: float, octaves: int, seed_value: int) -> float:
	var value = 0.0
	var amplitude = 0.5
	var frequency = 8.0
	
	for _i in range(octaves):
		value += noise(x * frequency, y * frequency, seed_value) * amplitude
		frequency *= 2.0
		amplitude *= 0.5
	
	return value

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

func generate_planet_palette(theme: int, seed_value: int) -> PackedColorArray:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	match theme:
		PlanetTheme.ARID:
			return PackedColorArray([
				Color(0.90, 0.70, 0.40),
				Color(0.82, 0.58, 0.35),
				Color(0.75, 0.47, 0.30),
				Color(0.70, 0.42, 0.25),
				Color(0.63, 0.38, 0.22),
				Color(0.53, 0.30, 0.16),
				Color(0.40, 0.23, 0.12)
			])
		
		PlanetTheme.LAVA:
			return PackedColorArray([
				Color(1.0, 0.6, 0.0),
				Color(0.9, 0.4, 0.05),
				Color(0.8, 0.2, 0.05),
				Color(0.7, 0.1, 0.05),
				Color(0.55, 0.08, 0.04),
				Color(0.4, 0.06, 0.03),
				Color(0.25, 0.04, 0.02)
			])
		
		PlanetTheme.LUSH:
			return PackedColorArray([
				Color(0.20, 0.70, 0.30),
				Color(0.18, 0.65, 0.25),
				Color(0.15, 0.60, 0.20),
				Color(0.12, 0.55, 0.15),
				Color(0.10, 0.50, 0.10),
				Color(0.35, 0.50, 0.70),
				Color(0.30, 0.45, 0.65),
				Color(0.25, 0.40, 0.60)
			])
		
		PlanetTheme.ICE:
			return PackedColorArray([
				Color(0.98, 0.99, 1.0),
				Color(0.92, 0.97, 1.0),
				Color(0.85, 0.92, 0.98),
				Color(0.75, 0.85, 0.95),
				Color(0.60, 0.75, 0.90),
				Color(0.45, 0.65, 0.85),
				Color(0.30, 0.50, 0.75)
			])
		
		PlanetTheme.DESERT:
			return PackedColorArray([
				Color(0.88, 0.72, 0.45),
				Color(0.85, 0.68, 0.40),
				Color(0.80, 0.65, 0.38),
				Color(0.75, 0.60, 0.35),
				Color(0.70, 0.55, 0.30),
				Color(0.65, 0.50, 0.28),
				Color(0.60, 0.45, 0.25),
				Color(0.48, 0.35, 0.20)
			])
		
		PlanetTheme.ALPINE:
			return PackedColorArray([
				Color(0.98, 0.98, 0.98),
				Color(0.95, 0.95, 0.97),
				Color(0.90, 0.90, 0.95),
				Color(0.85, 0.85, 0.90),
				Color(0.80, 0.85, 0.80),
				Color(0.75, 0.85, 0.75),
				Color(0.70, 0.80, 0.70),
				Color(0.65, 0.75, 0.65)
			])
		
		PlanetTheme.OCEAN:
			return PackedColorArray([
				Color(0.10, 0.35, 0.65),
				Color(0.15, 0.40, 0.70),
				Color(0.15, 0.45, 0.75),
				Color(0.18, 0.50, 0.80),
				Color(0.20, 0.55, 0.85),
				Color(0.25, 0.60, 0.88),
				Color(0.30, 0.65, 0.90),
				Color(0.40, 0.75, 0.95)
			])
		
		_:
			return PackedColorArray([
				Color(0.5, 0.5, 0.5),
				Color(0.6, 0.6, 0.6),
				Color(0.4, 0.4, 0.4),
				Color(0.7, 0.7, 0.7),
				Color(0.3, 0.3, 0.3)
			])

func create_empty_atmosphere() -> Image:
	var empty_atmosphere = Image.create(1, 1, true, Image.FORMAT_RGBA8)
	empty_atmosphere.set_pixel(0, 0, Color(0, 0, 0, 0))
	return empty_atmosphere

func create_planet_texture(seed_value: int) -> Array:
	var planet_size = PLANET_SIZE_LARGE
	var image = Image.create(planet_size, planet_size, true, Image.FORMAT_RGBA8)
	
	var current_theme = get_planet_theme(seed_value)
	var colors = generate_planet_palette(current_theme, seed_value)
	var planet_radius = PLANET_RADIUS
	
	var aa_width = 1.5
	var aa_width_normalized = aa_width / planet_radius
	
	var variation_seed_1 = seed_value + 12345
	var variation_seed_2 = seed_value + 67890
	
	var color_size = colors.size() - 1
	var half_size = planet_size / 2.0
	var planet_size_minus_one = planet_size - 1
	
	for y in range(planet_size):
		var ny = float(y) / planet_size_minus_one
		var dy = ny - 0.5
		
		for x in range(planet_size):
			var nx = float(x) / planet_size_minus_one
			var dx = nx - 0.5
			
			var dist_squared = dx * dx + dy * dy
			var dist = sqrt(dist_squared)
			var normalized_dist = dist * 2.0
			
			if normalized_dist > 1.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
				
			var alpha = 1.0
			if normalized_dist > (1.0 - aa_width_normalized):
				alpha = 1.0 - (normalized_dist - (1.0 - aa_width_normalized)) / aa_width_normalized
				alpha = clamp(alpha, 0.0, 1.0)
			
			var sphere_uv = spherify(nx, ny)
			var base_noise = fbm(sphere_uv.x, sphere_uv.y, TERRAIN_OCTAVES, seed_value)
			
			var detail_variation_1 = fbm(sphere_uv.x * 3.0, sphere_uv.y * 3.0, 2, variation_seed_1) * 0.1
			var detail_variation_2 = fbm(sphere_uv.x * 5.0, sphere_uv.y * 5.0, 1, variation_seed_2) * 0.05
			
			var combined_noise = base_noise + detail_variation_1 + detail_variation_2
			combined_noise = clamp(combined_noise * COLOR_VARIATION, 0.0, 1.0)
			
			var color_index = int(combined_noise * color_size)
			color_index = clamp(color_index, 0, color_size)
			
			var final_color = colors[color_index]
			
			var edge_shade = 1.0 - pow(normalized_dist, 2) * 0.3
			final_color.r *= edge_shade
			final_color.g *= edge_shade
			final_color.b *= edge_shade
			
			final_color.a = alpha
			
			image.set_pixel(x, y, final_color)
	
	var empty_atmosphere = create_empty_atmosphere()
	
	return [
		ImageTexture.create_from_image(image),
		ImageTexture.create_from_image(empty_atmosphere),
		planet_size
	]
