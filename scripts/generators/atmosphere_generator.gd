# scripts/generators/atmosphere_generator.gd
extends RefCounted
class_name AtmosphereGenerator

enum PlanetTheme {
	ARID,
	ICE,
	LAVA,
	LUSH,
	DESERT,
	ALPINE,
	OCEAN
}

const BASE_ATMOSPHERE_SIZE: int = 384
const INNER_RADIUS_FACTOR: float = 0.97
const BASE_THICKNESS_FACTOR: float = 0.26

const ATMOSPHERE_COLORS = {
	PlanetTheme.ARID: Color(0.8, 0.6, 0.4, 0.3),
	PlanetTheme.ICE: Color(0.8, 0.9, 1.0, 0.2),
	PlanetTheme.LAVA: Color(0.9, 0.3, 0.1, 0.5),
	PlanetTheme.LUSH: Color(0.5, 0.8, 1.0, 0.3),
	PlanetTheme.DESERT: Color(0.9, 0.7, 0.4, 0.4),
	PlanetTheme.ALPINE: Color(0.7, 0.9, 1.0, 0.25),
	PlanetTheme.OCEAN: Color(0.4, 0.7, 0.9, 0.35)
}

const ATMOSPHERE_THICKNESS = {
	PlanetTheme.ARID: 1.1,
	PlanetTheme.ICE: 0.8,
	PlanetTheme.LAVA: 1.6,
	PlanetTheme.LUSH: 1.2,
	PlanetTheme.DESERT: 1.3,
	PlanetTheme.ALPINE: 0.9,
	PlanetTheme.OCEAN: 1.15
}

static var atmosphere_texture_cache: Dictionary = {}

func generate_atmosphere_data(theme: int, seed_value: int) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value + 54321
	
	var base_color = ATMOSPHERE_COLORS.get(theme, Color(0.5, 0.7, 0.9, 0.3))
	var base_thickness = ATMOSPHERE_THICKNESS.get(theme, 1.0)
	
	var color_variation = 0.1
	var thickness_variation = 0.2
	
	var r = clamp(base_color.r + (rng.randf() - 0.5) * color_variation, 0, 1)
	var g = clamp(base_color.g + (rng.randf() - 0.5) * color_variation, 0, 1)
	var b = clamp(base_color.b + (rng.randf() - 0.5) * color_variation, 0, 1)
	var a = clamp(base_color.a + (rng.randf() - 0.5) * color_variation * 0.5, 0.05, 0.8)
	
	var color = Color(r, g, b, a)
	var thickness = base_thickness * (1.0 + (rng.randf() - 0.5) * thickness_variation)
	
	if theme == PlanetTheme.LAVA:
		thickness *= 1.2
		color.a = min(color.a + 0.1, 0.8)
	
	if theme == PlanetTheme.OCEAN:
		color.g += 0.05
	
	return {
		"color": color,
		"thickness": thickness
	}

static func get_atmosphere_texture(theme: int, seed_value: int, color: Color, thickness: float) -> ImageTexture:
	var cache_key = str(theme) + "_" + str(seed_value)
	
	if atmosphere_texture_cache.has(cache_key):
		return atmosphere_texture_cache[cache_key]
	
	var generator = new()
	var texture = generator.generate_atmosphere_texture(theme, seed_value, color, thickness)
	
	atmosphere_texture_cache[cache_key] = texture
	
	if atmosphere_texture_cache.size() > 50:
		var oldest_key = atmosphere_texture_cache.keys()[0]
		atmosphere_texture_cache.erase(oldest_key)
	
	return texture

func generate_atmosphere_texture(theme: int, seed_value: int, color: Color, thickness_factor: float) -> ImageTexture:
	var atm_size = BASE_ATMOSPHERE_SIZE
	var image = Image.create(atm_size, atm_size, true, Image.FORMAT_RGBA8)
	
	var planet_radius = 127.0
	var inner_radius = planet_radius * INNER_RADIUS_FACTOR
	var thickness = planet_radius * BASE_THICKNESS_FACTOR * thickness_factor
	var outer_radius = planet_radius + thickness
	
	var center = Vector2(atm_size / 2.0, atm_size / 2.0)
	
	var _noise_scale = 0.0
	var noise_amount = 0.0
	var cloud_bands = false
	var dust_streaks = false
	
	match theme:
		PlanetTheme.LAVA:
			_noise_scale = 8.0
			noise_amount = 0.3
			cloud_bands = false
		PlanetTheme.ARID, PlanetTheme.DESERT:
			_noise_scale = 6.0
			noise_amount = 0.2
			dust_streaks = true
		PlanetTheme.OCEAN, PlanetTheme.LUSH:
			_noise_scale = 4.0
			noise_amount = 0.15
			cloud_bands = true
	
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value + 54321
	
	for y in range(atm_size):
		for x in range(atm_size):
			var pos = Vector2(x, y)
			var dist = pos.distance_to(center)
			
			if dist > outer_radius or dist < inner_radius:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			
			var atmosphere_t = (dist - inner_radius) / (outer_radius - inner_radius)
			var alpha_curve = 1.0 - atmosphere_t
			alpha_curve = alpha_curve * alpha_curve * (3.0 - 2.0 * alpha_curve)
			
			var noise_factor = 1.0
			if noise_amount > 0:
				var angle = atan2(y - center.y, x - center.x)
				var noise_value = 0.0
				
				if cloud_bands:
					noise_value = sin(angle * 2.0 + rng.randf() * TAU)
					noise_value = noise_value * 0.5 + 0.5
				elif dust_streaks:
					noise_value = sin(angle * 3.0 + cos(angle * 2.0) + rng.randf() * TAU)
					noise_value = noise_value * 0.5 + 0.5
				else:
					noise_value = sin(angle * rng.randf_range(2.0, 4.0) + rng.randf() * TAU)
					noise_value = noise_value * 0.5 + 0.5
				
				noise_factor = 1.0 - noise_amount + noise_value * noise_amount
			
			var final_alpha = color.a * alpha_curve * noise_factor
			
			if atmosphere_t > 0.85:
				final_alpha *= (1.0 - (atmosphere_t - 0.85) / 0.15)
			
			var final_color = Color(color.r, color.g, color.b, final_alpha)
			
			image.set_pixel(x, y, final_color)
	
	for y in range(atm_size):
		for x in range(atm_size):
			var pos = Vector2(x, y)
			var dist = pos.distance_to(center)
			
			if dist > outer_radius - 2.0 and dist < outer_radius + 2.0:
				var t = (dist - (outer_radius - 2.0)) / 4.0
				t = clamp(t, 0.0, 1.0)
				t = t * t * (3.0 - 2.0 * t)
				
				var pixel_color = image.get_pixel(x, y)
				pixel_color.a *= 1.0 - t
				
				image.set_pixel(x, y, pixel_color)
	
	return ImageTexture.create_from_image(image)

func get_atmosphere_color_for_theme(theme: int) -> Color:
	return ATMOSPHERE_COLORS.get(theme, Color(0.5, 0.7, 0.9, 0.3))

func get_atmosphere_thickness_for_theme(theme: int) -> float:
	return ATMOSPHERE_THICKNESS.get(theme, 1.0)
