# scripts/entities/planets/planet_gaseous.gd
# Specialized implementation for gaseous planets (gas giants)
extends "res://scripts/entities/planets/planet_base.gd"
class_name PlanetGaseous

# Gas giant types (same as in planet_generator_gaseous.gd for consistency)
enum GasGiantType {
	JUPITER = 0,  # Jupiter-like (beige/tan tones)
	SATURN = 1,   # Saturn-like (golden tones)
	NEPTUNE = 2,  # Neptune-like (blue tones)
	EXOTIC = 3    # Exotic (lavender tones)
}

# Gas giant specific properties
var gas_giant_type: int = GasGiantType.JUPITER

func _init() -> void:
	# CHANGED: Increased number of moons and adjusted orbit distances
	max_moons = 7  # Increased from 5 to 6-7 moons
	moon_chance = 100  # Always have moons
	min_moon_distance_factor = 2.5  # Increased from 2.0 - Moons orbit farther out
	max_moon_distance_factor = 3.5  # Increased from 2.8 - Maximum distance increased

# Override specialized initialization for gaseous planets
func _perform_specialized_initialization(params: Dictionary) -> void:
	# Create a local RNG for consistent random generation
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# For gaseous planets, the theme is always GAS_GIANT
	theme_id = PlanetThemes.GAS_GIANT
	
	# Determine gas giant type (Jupiter-like, Saturn-like, etc.)
	var giant_type_override = params.get("gas_giant_type_override", -1)
	if giant_type_override >= 0 and giant_type_override < 4:
		gas_giant_type = giant_type_override
	else:
		# Choose random type if not specified
		gas_giant_type = rng.randi() % 4
	
	# Generate or get planet textures
	_generate_planet_texture()
	
	# Generate or get atmosphere textures
	_generate_atmosphere_texture()
	
	# Set the pixel size for gaseous planets (larger)
	pixel_size = 512

# Generate gas giant planet texture
func _generate_planet_texture() -> void:
	# Create a unique identifier that includes both seed and gas giant type
	var unique_identifier = str(seed_value) + "_gas_" + str(gas_giant_type)
	
	if use_texture_cache and PlanetGeneratorBase.texture_cache.gaseous.has(unique_identifier):
		# Use cached texture
		var textures = PlanetGeneratorBase.texture_cache.gaseous[unique_identifier]
		planet_texture = textures[0]
	else:
		# Generate new texture using the specialized gaseous generator
		var generator = PlanetGeneratorGaseous.new()
		var textures = generator.create_planet_texture(seed_value, gas_giant_type)
		planet_texture = textures[0]
		
		# Cache the texture
		if use_texture_cache:
			PlanetGeneratorBase.texture_cache.gaseous[unique_identifier] = textures

# Generate atmosphere texture for gas giants
func _generate_atmosphere_texture() -> void:
	var atmosphere_generator = AtmosphereGenerator.new()
	
	# We need to create a seed that incorporates the gas giant type
	var adjusted_seed = seed_value + (gas_giant_type * 10000)
	
	atmosphere_data = atmosphere_generator.generate_atmosphere_data(PlanetThemes.GAS_GIANT, adjusted_seed)
	
	var unique_identifier = str(adjusted_seed) + "_atmo_gas"
	
	if use_texture_cache and PlanetGeneratorBase.texture_cache.atmospheres.has(unique_identifier):
		# Use cached atmosphere texture
		atmosphere_texture = PlanetGeneratorBase.texture_cache.atmospheres[unique_identifier]
	else:
		# Generate new atmosphere texture
		atmosphere_texture = atmosphere_generator.generate_atmosphere_texture(
			PlanetThemes.GAS_GIANT, adjusted_seed, atmosphere_data.color, atmosphere_data.thickness)
			
		# Cache the texture
		if use_texture_cache:
			PlanetGeneratorBase.texture_cache.atmospheres[unique_identifier] = atmosphere_texture

# Override to determine appropriate moon types for gas giants
func _get_moon_type_for_position(moon_position: int, total_moons: int, rng: RandomNumberGenerator) -> int:
	# CHANGED: Updated distribution for better variety
	# Distribute moon types based on position in orbit
	if moon_position == 0:
		return MoonType.LAVA  # Innermost moon (volcanic due to tidal forces)
	elif moon_position < total_moons / 3:
		return MoonType.ROCKY  # Inner moons are rocky
	elif moon_position < 2 * total_moons / 3:
		# Mix of rocky and ice in the middle region
		return MoonType.ROCKY if rng.randf() < 0.5 else MoonType.ICE
	else:
		return MoonType.ICE  # Outer moons are icy (colder as they're further away)

# Override for moon size scale - use new system with fixed sizes instead
func _get_moon_size_scale() -> float:
	return 1.0  # We now use properly sized moon textures directly

# Override for orbit speed - gas giants have slower orbiting moons due to mass
func _get_orbit_speed_modifier() -> float:
	return 0.7  # 30% slower than terran planets (increased slowdown)

# Override to return appropriate planet type name
func _get_planet_type_name() -> String:
	return "Gas Giant"

# CHANGED: Override _generate_orbital_parameters for better moon spacing
func _generate_orbital_parameters(moon_count: int, rng: RandomNumberGenerator) -> Array:
	var params = []
	
	if moon_count <= 0:
		return params
	
	# Calculate planet radius for reference
	var planet_radius = pixel_size / 2.0
	
	# Define distance range based on planet size
	var min_distance = planet_radius * min_moon_distance_factor
	var max_distance = planet_radius * max_moon_distance_factor
	
	# For multiple moons, use intelligent parameter distribution
	if moon_count > 1:
		# Step 1: Improved distance spacing formula for gaseous planets
		# Distribute distances with increasing gaps to avoid crowding
		for i in range(moon_count):
			# Use a quadratic distribution to space moons farther as they get farther out
			var t = float(i) / float(moon_count - 1)
			
			# Quadratic spacing gives more room between outer moons
			var distance_factor = min_distance + (max_distance - min_distance) * (t * t * 0.7 + t * 0.3)
			
			# Add some randomness to prevent perfect spacing
			var jitter_range = 0.05  # 5% jitter maximum 
			var jitter = distance_factor * jitter_range * rng.randf_range(-1.0, 1.0)
			var distance = clamp(distance_factor + jitter, min_distance, max_distance)
			
			# Step 2: Calculate orbital speed based on distance (approximating Kepler's law)
			# Closer moons orbit faster (sqrt relationship)
			var speed_factor = 1.0 / sqrt(distance / min_distance)
			
			# Adjust for planet mass
			var orbit_speed = rng.randf_range(0.15, 0.3) * moon_orbit_factor * speed_factor * _get_orbit_speed_modifier()
			
			# Step 3: Distribute phase offsets evenly around orbit
			# This ensures moons start at different positions
			var phase_offset = (i * TAU / moon_count) + rng.randf_range(-0.1, 0.1)
			
			# Step 4: Set orbit deviation (for elliptical orbits)
			# Larger deviation for farther moons
			var orbit_deviation = rng.randf_range(0.05, max_orbit_deviation) * (distance / max_distance)
			
			params.append({
				"distance": distance,
				"base_angle": 0.0, # Start at same position, but phase_offset will separate them
				"orbit_speed": orbit_speed,
				"orbit_deviation": orbit_deviation,
				"phase_offset": phase_offset
			})
	else:
		# For a single moon, use simpler parameters
		params.append({
			"distance": rng.randf_range(min_distance, max_distance),
			"base_angle": 0.0,
			"orbit_speed": rng.randf_range(0.15, 0.3) * moon_orbit_factor * _get_orbit_speed_modifier(),
			"orbit_deviation": rng.randf_range(0.05, max_orbit_deviation),
			"phase_offset": rng.randf_range(0, TAU) # Random starting position
		})
	
	return params

# Override moon creation to use correct sizing for gaseous planet moons
func _create_moons() -> void:
	if not _moon_scene:
		push_error("Planet: Moon scene not available for moon creation")
		emit_signal("planet_loaded", self)
		return
	
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# Determine if this planet has moons based on chance
	var has_moons = (rng.randi() % 100 < moon_chance)
	var num_moons = 0
	
	if has_moons:
		# Calculate how many moons (1 to max_moons)
		num_moons = rng.randi_range(6, max_moons)  # CHANGED: Minimum 6 moons for gas giants
	
	# If no moons, exit early
	if num_moons <= 0:
		emit_signal("planet_loaded", self)
		return
	
	# Generate orbital parameters for all moons to prevent collisions
	var orbital_params = _generate_orbital_parameters(num_moons, rng)
	
	for m in range(num_moons):
		var moon_seed = seed_value + m * 100 + rng.randi() % 1000
		
		var moon_instance = _moon_scene.instantiate()
		if not moon_instance:
			continue
		
		# Determine moon type based on position
		var moon_type = _get_moon_type_for_position(m, num_moons, rng)
		
		# Use the pre-calculated orbital parameters
		var moon_params = {
			"seed_value": moon_seed,
			"parent_planet": self,
			"distance": orbital_params[m].distance,
			"base_angle": orbital_params[m].base_angle,
			"orbit_speed": orbital_params[m].orbit_speed,
			"orbit_deviation": orbital_params[m].orbit_deviation,
			"phase_offset": orbital_params[m].phase_offset,
			"parent_name": planet_name,
			"use_texture_cache": use_texture_cache,
			"moon_type": moon_type,
			"is_gaseous": true  # CHANGED: Mark that this moon belongs to a gaseous planet
		}
		
		add_child(moon_instance)
		moon_instance.initialize(moon_params)
		moons.append(moon_instance)
	
	# Emit signal that the planet has been loaded (after moons are created)
	emit_signal("planet_loaded", self)

# Get gas giant type name for UI and debugging
func get_gas_giant_type_name() -> String:
	match gas_giant_type:
		GasGiantType.JUPITER: return "Jupiter-like"
		GasGiantType.SATURN: return "Saturn-like"
		GasGiantType.NEPTUNE: return "Neptune-like"
		GasGiantType.EXOTIC: return "Exotic"
		_: return "Unknown"

# Return planet category
func get_category() -> int:
	return PlanetCategories.GASEOUS

# Return category name as string (for debugging/UI)
func get_category_name() -> String:
	return "Gaseous"
