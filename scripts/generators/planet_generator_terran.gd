# scripts/generators/planet_generator_terran.gd
# ===========================
# Purpose:
#   Specialized generator for terran planet textures
#   Handles detailed terrain generation for various terran themes
#   Creates realistic planet surfaces with varied biomes and features
#
# Dependencies:
#   - planet_generator_base.gd
#
extends PlanetGeneratorBase
class_name PlanetGeneratorTerran

# Constants specific to terran planet generation
const BIOME_VARIATION: float = 1.8
const DETAIL_SCALE: float = 3.0

# Get or generate a terran planet texture
static func get_terran_texture(seed_value: int, theme_override: int = -1) -> Array:
	var cache_key = str(seed_value) + "_theme_" + str(theme_override)
	
	if texture_cache.terran.has(cache_key):
		return texture_cache.terran[cache_key]
	
	var generator = PlanetGeneratorTerran.new()
	var textures = generator.create_planet_texture(seed_value, theme_override)
	
	texture_cache.terran[cache_key] = textures
	clean_texture_cache()
	
	return textures

# Generate appropriate color palette for different terran planet themes
func generate_terran_palette(theme: int, seed_value: int) -> PackedColorArray:
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
			# Fallback for unknown themes
			return PackedColorArray([
				Color(0.5, 0.5, 0.5),
				Color(0.6, 0.6, 0.6),
				Color(0.4, 0.4, 0.4),
				Color(0.7, 0.7, 0.7),
				Color(0.3, 0.3, 0.3)
			])

# Generate terran planet texture
func create_planet_texture(seed_value: int, explicit_theme: int = -1) -> Array:
	var theme = explicit_theme if explicit_theme >= 0 else get_planet_theme(seed_value)
	
	# Only proceed if this is a terran theme (not JUPITER or other gas giants)
	if theme >= PlanetTheme.JUPITER:
		push_warning("PlanetGeneratorTerran: Requested gaseous planet theme, using a random terran theme instead")
		var rng = RandomNumberGenerator.new()
		rng.seed = seed_value
		theme = rng.randi() % PlanetTheme.JUPITER
	
	# Set up for terran planet generation
	var planet_size = PLANET_SIZE_TERRAN
	var image = Image.create(planet_size, planet_size, true, Image.FORMAT_RGBA8)
	var colors = generate_terran_palette(theme, seed_value)
	
	var variation_seed_1 = seed_value + 12345
	var variation_seed_2 = seed_value + 67890
	
	var color_size = colors.size() - 1
	var planet_size_minus_one = planet_size - 1
	
	# Main texture generation loop for terran planet
	for y in range(planet_size):
		var ny = float(y) / planet_size_minus_one
		var dy = ny - 0.5
		
		for x in range(planet_size):
			var nx = float(x) / planet_size_minus_one
			var dx = nx - 0.5
			
			var dist_squared = dx * dx + dy * dy
			var dist = sqrt(dist_squared)
			var normalized_dist = dist * 2.0
			
			# PIXEL-PERFECT EDGE: Use a hard cutoff instead of anti-aliasing
			if normalized_dist >= 1.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			
			# Inside the planet - full alpha
			var alpha = 1.0
			
			var sphere_uv = spherify(nx, ny)
			
			# TERRAN PLANET GENERATION
			var base_noise = fbm(sphere_uv.x, sphere_uv.y, TERRAIN_OCTAVES, seed_value)
			var detail_variation_1 = fbm(sphere_uv.x * DETAIL_SCALE, sphere_uv.y * DETAIL_SCALE, 2, variation_seed_1) * 0.1
			var detail_variation_2 = fbm(sphere_uv.x * (DETAIL_SCALE + 2.0), sphere_uv.y * (DETAIL_SCALE + 2.0), 1, variation_seed_2) * 0.05
			
			var combined_noise = base_noise + detail_variation_1 + detail_variation_2
			combined_noise = clamp(combined_noise * BIOME_VARIATION, 0.0, 1.0)
			
			var color_index = int(combined_noise * color_size)
			color_index = clamp(color_index, 0, color_size)
			
			var final_color = colors[color_index]
			
			# Create edge shading (darker at edges)
			var edge_shade = 1.0 - pow(normalized_dist, 2) * 0.3
			final_color.r *= edge_shade
			final_color.g *= edge_shade
			final_color.b *= edge_shade
			
			# Apply alpha for pixel-perfect edge
			final_color.a = alpha
			
			image.set_pixel(x, y, final_color)
	
	# Create empty atmosphere placeholder (atmosphere is handled elsewhere)
	var empty_atmosphere = create_empty_atmosphere()
	
	# Return the generated textures
	return [
		ImageTexture.create_from_image(image),
		ImageTexture.create_from_image(empty_atmosphere),
		planet_size
	]
