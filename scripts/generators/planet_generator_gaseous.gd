# scripts/generators/planet_generator_gaseous.gd
# ============================
# Purpose:
#   Specialized generator for gaseous planets (gas giants)
#   Creates detailed planet textures with band patterns and atmospheric effects
#   Handles different gas giant types: Jupiter-like, Saturn-like, Neptune-like and Exotic

extends PlanetGeneratorBase
class_name PlanetGeneratorGaseous

# Gas giant type enum
enum GasGiantType {
	JUPITER = 0,  # Jupiter-like (beige/tan tones)
	SATURN = 1,   # Saturn-like (golden tones)
	NEPTUNE = 2,  # Neptune-like (blue tones)
	EXOTIC = 3    # Exotic (lavender tones)
}

# Gas giant specific constants
const GAS_GIANT_BANDS: int = 12         # Number of primary bands
const GAS_GIANT_BAND_NOISE: float = 0.5  # How noisy the bands are
const GAS_GIANT_FLOW: float = 2.0       # How much the bands "flow" horizontally
const BAND_SIZE_VARIATION: float = 0.3   # Variation in band sizes

# Type-specific configuration - allows fine-tuning for each gas giant type
var type_configs = {
	GasGiantType.JUPITER: {
		"bands": 18,
		"noise_strength": 0.5,
		"flow": 2.5,
		"storm_chance": 0.7,
		"storm_size_range": Vector2(0.05, 0.12),
		"polar_cap_size": 0.15,
		"color_variation": 0.2
	},
	GasGiantType.SATURN: {
		"bands": 15,
		"noise_strength": 0.4,
		"flow": 3.0,
		"storm_chance": 0.4,
		"storm_size_range": Vector2(0.03, 0.08),
		"polar_cap_size": 0.12,
		"color_variation": 0.25
	},
	GasGiantType.NEPTUNE: {
		"bands": 10,
		"noise_strength": 0.6,
		"flow": 3.5,
		"storm_chance": 0.5,
		"storm_size_range": Vector2(0.04, 0.10),
		"polar_cap_size": 0.2,
		"color_variation": 0.2
	},
	GasGiantType.EXOTIC: {
		"bands": 14,
		"noise_strength": 0.7,
		"flow": 2.0,
		"storm_chance": 0.8,
		"storm_size_range": Vector2(0.06, 0.15),
		"polar_cap_size": 0.18,
		"color_variation": 0.3
	}
}

# Type-specific color palettes
var type_colors = {
	GasGiantType.JUPITER: [
		Color(0.83, 0.78, 0.65),  # Light beige
		Color(0.80, 0.73, 0.60),  # Beige
		Color(0.77, 0.68, 0.55),  # Darker beige
		Color(0.74, 0.63, 0.50),  # Light tan
		Color(0.71, 0.58, 0.45),  # Tan
		Color(0.68, 0.53, 0.40),  # Dark tan
		Color(0.65, 0.48, 0.35),  # Light brown
		Color(0.62, 0.43, 0.30)   # Brown
	],
	GasGiantType.SATURN: [
		Color(0.85, 0.82, 0.70),  # Pale gold
		Color(0.83, 0.80, 0.66),  # Light gold
		Color(0.81, 0.78, 0.62),  # Gold
		Color(0.79, 0.76, 0.58),  # Muted gold
		Color(0.77, 0.74, 0.54),  # Darker gold
		Color(0.75, 0.72, 0.50),  # Dusky gold
		Color(0.73, 0.70, 0.46),  # Golden tan
		Color(0.71, 0.68, 0.42)   # Dark golden tan
	],
	GasGiantType.NEPTUNE: [
		Color(0.60, 0.75, 0.85),  # Light blue
		Color(0.55, 0.72, 0.83),  # Sky blue
		Color(0.50, 0.69, 0.81),  # Azure
		Color(0.45, 0.66, 0.79),  # Medium blue
		Color(0.40, 0.63, 0.77),  # Blue
		Color(0.35, 0.60, 0.75),  # Deep blue
		Color(0.30, 0.57, 0.73),  # Dark blue
		Color(0.25, 0.54, 0.71)   # Navy blue
	],
	GasGiantType.EXOTIC: [
		Color(0.75, 0.70, 0.85),  # Very light lavender
		Color(0.70, 0.65, 0.83),  # Light lavender
		Color(0.65, 0.60, 0.81),  # Lavender
		Color(0.60, 0.55, 0.79),  # Medium lavender
		Color(0.55, 0.50, 0.77),  # Dusky lavender
		Color(0.50, 0.45, 0.75),  # Light purple
		Color(0.45, 0.40, 0.73),  # Purple
		Color(0.40, 0.35, 0.71)   # Deep purple
	]
}

# Predefined storm features for gas giants
var storm_colors = {
	GasGiantType.JUPITER: Color(0.95, 0.85, 0.70, 0.9),  # Jupiter's Great Red Spot color
	GasGiantType.SATURN: Color(0.90, 0.87, 0.75, 0.9),   # Saturn's vortex color
	GasGiantType.NEPTUNE: Color(0.70, 0.85, 0.95, 0.9),  # Neptune's dark spot color
	GasGiantType.EXOTIC: Color(0.85, 0.75, 0.95, 0.9)    # Exotic purple storm color
}

func _init():
	# Any gaseous-specific initialization can go here
	pass

# Generate a random gas giant type
func get_random_giant_type(seed_value: int) -> int:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng.randi() % 4  # 0-3 for the gas giant types

# Main function to generate a gaseous planet texture
func generate_planet_texture(seed_value: int, giant_type: int = -1) -> Array:
	# If giant_type is negative, generate a random one
	if giant_type < 0:
		giant_type = get_random_giant_type(seed_value)
	else:
		# Ensure it's a valid type (0-3)
		giant_type = giant_type % 4
	
	# Check cache first - include the giant type in the key
	var cache_key = str(seed_value) + "_gas_" + str(giant_type)
	if texture_cache.planets.has(cache_key):
		return [texture_cache.planets[cache_key], null, PLANET_SIZE_GASEOUS]
	
	# Create the planet image
	var image = Image.create(PLANET_SIZE_GASEOUS, PLANET_SIZE_GASEOUS, true, Image.FORMAT_RGBA8)
	
	# Get colors for this giant type
	var colors = type_colors[giant_type]
	var config = type_configs[giant_type]
	
	# Cache for noise calculations
	var noise_cache = {}
	
	# Variation seeds for different noise patterns
	var band_seed = seed_value + 12345
	var flow_seed = seed_value + 54321
	var storm_seed = seed_value + 99999
	
	# Optimization: precalculate noise values for bands for each y coordinate
	var band_values = []
	for y in range(PLANET_SIZE_GASEOUS):
		var ny = float(y) / (PLANET_SIZE_GASEOUS - 1)
		var y_centered = ny * 2.0 - 1.0  # -1 to 1
		
		# Base band pattern using the y coordinate
		var band_value = sin(y_centered * PI * config.bands)
		
		# Add noise to band edges
		var noise_y = ny * 5.0
		var band_noise = _generate_fbm(0, noise_y, 2, band_seed, noise_cache) * config.noise_strength
		band_value = (band_value + band_noise) * 0.5 + 0.5  # Normalize to 0-1
		
		band_values.append(band_value)
	
	# Generate storms if they should appear for this planet
	var storms = _generate_storms(giant_type, seed_value, config, noise_cache)
	
	# Planet edge cutoff optimization - precompute circle distances
	var center = Vector2(PLANET_SIZE_GASEOUS / 2.0, PLANET_SIZE_GASEOUS / 2.0)
	var distances = {}
	for y in range(PLANET_SIZE_GASEOUS):
		distances[y] = {}
		var dy = (y - center.y) / center.y  # -1 to 1
		
		for x in range(PLANET_SIZE_GASEOUS):
			var dx = (x - center.x) / center.x  # -1 to 1
			var dist = sqrt(dx * dx + dy * dy)
			distances[y][x] = dist
	
	# Main texture generation loop
	for y in range(PLANET_SIZE_GASEOUS):
		var ny = float(y) / (PLANET_SIZE_GASEOUS - 1)
		
		# Use the precalculated band value
		var base_band_value = band_values[y]
		
		for x in range(PLANET_SIZE_GASEOUS):
			var nx = float(x) / (PLANET_SIZE_GASEOUS - 1)
			
			# Check if outside planet using precalculated distances
			var dist = distances[y][x]
			if dist > 1.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			
			# Calculate flow effect (horizontal distortion) for this x position
			var flow_x = nx * 8.0
			var flow_noise = _generate_fbm(flow_x, ny * 3.0, 2, flow_seed, noise_cache) * config.flow
			
			# Apply flow to the x coordinate
			var distorted_x = nx + flow_noise * 0.05
			distorted_x = fmod(distorted_x, 1.0)  # Wrap around 0-1
			
			# Adjust band value with flow
			var band_value = base_band_value
			
			# Check if this pixel is part of a storm
			var in_storm = false
			var storm_color = Color(0,0,0,0)
			
			for storm in storms:
				var storm_x = storm.center.x
				var storm_y = storm.center.y
				var storm_size = storm.size
				
				var dx = nx - storm_x
				var dy = ny - storm_y
				
				# Account for wrapping around the planet
				if dx > 0.5: dx -= 1.0
				if dx < -0.5: dx += 1.0
				
				var dist_squared = dx*dx + dy*dy
				
				if dist_squared < storm_size * storm_size:
					in_storm = true
					
					# Calculate gradient within storm
					var storm_dist = sqrt(dist_squared) / storm_size
					var gradient = 1.0 - storm_dist  # 1 at center, 0 at edge
					
					# Apply swirl effect
					var angle = atan2(dy, dx) + gradient * 5.0
					
					# Storm color with some variation
					storm_color = storm.color
					storm_color.a = clamp(gradient * 1.2, 0, 1)
					break
			
			# Determine final color based on band value
			var color_index = 0
			
			if in_storm:
				# Use the storm color
				var band_color = colors[int(band_value * (colors.size() - 1))]
				# Blend the band color with the storm color
				var final_color = band_color.lerp(storm_color, storm_color.a)
				final_color.a = 1.0  # Fully opaque
				
				# Apply edge darkening
				var edge_shade = 1.0 - pow(dist, 2) * 0.2
				final_color.r *= edge_shade
				final_color.g *= edge_shade
				final_color.b *= edge_shade
				
				image.set_pixel(x, y, final_color)
			else:
				# Standard band coloring
				color_index = int(band_value * (colors.size() - 1))
				color_index = clamp(color_index, 0, colors.size() - 1)
				
				var final_color = colors[color_index]
				
				# Apply edge darkening
				var edge_shade = 1.0 - pow(dist, 2) * 0.2
				final_color.r *= edge_shade
				final_color.g *= edge_shade
				final_color.b *= edge_shade
				
				final_color.a = 1.0  # Fully opaque
				image.set_pixel(x, y, final_color)
	
	# Create the texture
	var texture = ImageTexture.create_from_image(image)
	
	# Cache the result - use gas giant type in the key
	texture_cache.planets[cache_key] = texture
	cleanup_cache()
	
	# Return the texture array
	return [texture, null, PLANET_SIZE_GASEOUS]

# Generate storm systems for gas giants
func _generate_storms(giant_type: int, seed_value: int, config: Dictionary, noise_cache: Dictionary) -> Array:
	var storms = []
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# Determine if this planet will have storms
	if rng.randf() < config.storm_chance:
		# Generate 1-3 storms
		var storm_count = rng.randi_range(1, 3)
		
		for i in range(storm_count):
			var storm = {
				"center": Vector2(rng.randf(), rng.randf_range(0.3, 0.7)),  # Mostly in middle bands
				"size": rng.randf_range(config.storm_size_range.x, config.storm_size_range.y),
				"color": storm_colors[giant_type]
			}
			
			# Add some color variation
			var hue_shift = rng.randf_range(-0.05, 0.05)
			var h = storm.color.h + hue_shift
			var s = storm.color.s + rng.randf_range(-0.1, 0.1)
			var v = storm.color.v + rng.randf_range(-0.1, 0.1)
			
			storm.color = Color.from_hsv(h, clamp(s, 0, 1), clamp(v, 0, 1), storm.color.a)
			
			storms.append(storm)
	}
	
	return storms

# Generate fractal Brownian motion noise with multiple octaves
func _generate_fbm(x: float, y: float, octaves: int, seed_value: int, noise_cache: Dictionary) -> float:
	var value = 0.0
	var amplitude = 0.5
	var frequency = 4.0
	
	for _i in range(octaves):
		value += _generate_noise(x * frequency, y * frequency, seed_value, noise_cache) * amplitude
		frequency *= 2.0
		amplitude *= 0.5
	
	return value

# Generate smooth noise
func _generate_noise(x: float, y: float, seed_value: int, noise_cache: Dictionary) -> float:
	var ix = floor(x)
	var iy = floor(y)
	var fx = x - ix
	var fy = y - iy
	
	# Improved smoothing function for gas bands
	var u = smoothstep(0, 1, fx)
	var v = smoothstep(0, 1, fy)
	
	var a = get_random_seed(ix, iy, seed_value, noise_cache)
	var b = get_random_seed(ix + 1.0, iy, seed_value, noise_cache)
	var c = get_random_seed(ix, iy + 1.0, seed_value, noise_cache)
	var d = get_random_seed(ix + 1.0, iy + 1.0, seed_value, noise_cache)
	
	return lerp(
		lerp(a, b, u),
		lerp(c, d, u),
		v
	)

# Smoother interpolation specifically for gas bands
func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
