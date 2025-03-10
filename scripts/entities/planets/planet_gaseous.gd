# scripts/entities/planets/planet_gaseous.gd
# Specialized implementation for gaseous planets (gas giants)
extends PlanetBase
class_name PlanetGaseous

func _init() -> void:
	# Fixed number of moons for all gaseous planets
	max_moons = 7  # Always use 7 moons
	moon_chance = 100  # Always have moons
	min_moon_distance_factor = 1.3  # Reduced: Moons orbit much closer (was 2.5)
	max_moon_distance_factor = 1.8  # Reduced: Maximum distance decreased (was 3.5)

# Override specialized initialization for gaseous planets
func _perform_specialized_initialization(params: Dictionary) -> void:
	# Create a local RNG for consistent random generation
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# For gaseous planets, determine specific theme
	var theme_override = params.get("theme_override", -1)
	
	# Handle backwards compatibility with old gas_giant_type_override parameter
	var gas_giant_type_override = params.get("gas_giant_type_override", -1)
	if gas_giant_type_override >= 0 and gas_giant_type_override < 4:
		# Map from the old style (0-3) to the new enum values
		theme_override = PlanetThemes.JUPITER + gas_giant_type_override
	
	# Set the theme based on parameters or randomize
	if theme_override >= PlanetThemes.JUPITER and theme_override <= PlanetThemes.NEPTUNE:
		# Valid gaseous planet theme provided
		theme_id = theme_override
	else:
		# Choose a random gaseous theme
		theme_id = PlanetThemes.JUPITER + rng.randi() % 4
	
	# Generate or get planet textures
	_generate_planet_texture()
	
	# Generate or get atmosphere textures
	_generate_atmosphere_texture()
	
	# Set the pixel size for gaseous planets (larger)
	pixel_size = 512

# Generate gas giant planet texture
func _generate_planet_texture() -> void:
	# Create a unique identifier that includes the theme
	var unique_identifier = str(seed_value) + "_theme_" + str(theme_id)
	
	if use_texture_cache and PlanetGeneratorBase.texture_cache.has("gaseous") and PlanetGeneratorBase.texture_cache.gaseous.has(unique_identifier):
		# Use cached texture
		var textures = PlanetGeneratorBase.texture_cache.gaseous[unique_identifier]
		planet_texture = textures[0]
	else:
		# Generate new texture using the specialized gaseous generator
		var generator = PlanetGeneratorGaseous.new()
		var textures = generator.create_planet_texture(seed_value, theme_id)
		planet_texture = textures[0]
		
		# Cache the texture
		if use_texture_cache:
			if not PlanetGeneratorBase.texture_cache.has("gaseous"):
				PlanetGeneratorBase.texture_cache["gaseous"] = {}
			PlanetGeneratorBase.texture_cache.gaseous[unique_identifier] = textures

# Generate atmosphere texture for gas giants
func _generate_atmosphere_texture() -> void:
	var atmosphere_generator = AtmosphereGenerator.new()
	
	# Pass the correct theme ID directly (no need for adjusted seed)
	atmosphere_data = atmosphere_generator.generate_atmosphere_data(theme_id, seed_value)
	
	var unique_identifier = str(seed_value) + "_atmo_" + str(theme_id)
	
	if use_texture_cache and PlanetGeneratorBase.texture_cache.has("atmospheres") and PlanetGeneratorBase.texture_cache.atmospheres.has(unique_identifier):
		# Use cached atmosphere texture
		atmosphere_texture = PlanetGeneratorBase.texture_cache.atmospheres[unique_identifier]
	else:
		# Generate new atmosphere texture
		atmosphere_texture = atmosphere_generator.generate_atmosphere_texture(
			theme_id, seed_value, atmosphere_data.color, atmosphere_data.thickness)
			
		# Cache the texture
		if use_texture_cache:
			if not PlanetGeneratorBase.texture_cache.has("atmospheres"):
				PlanetGeneratorBase.texture_cache["atmospheres"] = {}
			PlanetGeneratorBase.texture_cache.atmospheres[unique_identifier] = atmosphere_texture

# Override to determine appropriate moon types for gas giants
func _get_moon_type_for_position(moon_position: int, total_moons: int, rng: RandomNumberGenerator) -> int:
	# Distribute moon types based on position in orbit
	if moon_position == 0:
		return MoonType.VOLCANIC  # Innermost moon (volcanic due to tidal forces)
	elif moon_position < int(float(total_moons) / 3.0):
		return MoonType.ROCKY  # Inner moons are rocky
	elif moon_position < int(2.0 * float(total_moons) / 3.0):
		# Mix of rocky and ice in the middle region
		return MoonType.ROCKY if rng.randf() < 0.5 else MoonType.ICY
	else:
		return MoonType.ICY  # Outer moons are icy (colder as they're further away)

# Override for moon size scale - use new system with fixed sizes instead
func _get_moon_size_scale() -> float:
	return 1.0  # We now use properly sized moon textures directly

# Override for orbit speed - gas giants have slower orbiting moons due to mass
func _get_orbit_speed_modifier() -> float:
	return 0.7  # 30% slower than terran planets (increased slowdown)

# Override to return appropriate planet type name
func _get_planet_type_name() -> String:
	return PlanetGeneratorBase.get_theme_name(theme_id)

# Generate evenly distributed orbital parameters for moons
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
		# Improved spacing formula with REDUCED gaps between moons for gaseous planets
		for i in range(moon_count):
			# Use a LESS quadratic distribution to space moons closer together
			var t = float(i) / float(moon_count - 1)
			
			# More linear spacing to keep moons visibly grouped
			var distance_factor = min_distance + (max_distance - min_distance) * (t * 0.6 + t * t * 0.4)
			
			# Reduce the jitter to keep moons in more consistent orbits
			var jitter_range = 0.03  # Reduced jitter (was 0.05)
			var jitter = distance_factor * jitter_range * rng.randf_range(-1.0, 1.0)
			var distance = clamp(distance_factor + jitter, min_distance, max_distance)
			
			# Calculate orbital speed based on distance
			var speed_factor = 1.0 / sqrt(distance / min_distance)
			var orbit_speed = rng.randf_range(0.15, 0.3) * moon_orbit_factor * speed_factor * _get_orbit_speed_modifier()
			
			# Distribute phase offsets evenly around orbit
			var phase_offset = (i * TAU / float(moon_count)) + rng.randf_range(-0.1, 0.1)
			
			# Set orbit deviation (for elliptical orbits)
			var orbit_deviation = rng.randf_range(0.05, max_orbit_deviation) * (distance / max_distance)
			
			params.append({
				"distance": distance,
				"base_angle": 0.0,
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

# Override moon creation to guarantee one of each type and use correct sizing
func _create_moons() -> void:
	if _moon_scenes.is_empty():
		push_error("Planet: Moon scenes not available for moon creation")
		emit_signal("planet_loaded", self)
		return
	
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# Always use 7 moons for gaseous planets
	var num_moons = 7
	
	# Generate orbital parameters for all moons to prevent collisions
	var orbital_params = _generate_orbital_parameters(num_moons, rng)
	
	# Track created moons
	moons.clear()
	
	# First 3 moons are guaranteed to be one of each type
	var guaranteed_types = [MoonType.ROCKY, MoonType.ICY, MoonType.VOLCANIC]
	for i in range(3):
		var moon_seed = seed_value + i * 100 + rng.randi() % 1000
		var moon_type = guaranteed_types[i]
		
		# Get the correct moon scene for this type
		if not _moon_scenes.has(moon_type):
			push_warning("Planet: Moon type not available: " + str(moon_type) + ", using ROCKY")
			moon_type = MoonType.ROCKY
			
		if not _moon_scenes.has(moon_type):
			push_error("Planet: No moon scenes available")
			continue
			
		var moon_scene = _moon_scenes[moon_type]
		if not moon_scene:
			continue
			
		var moon_instance = moon_scene.instantiate()
		if not moon_instance:
			continue
		
		# Use the pre-calculated orbital parameters
		var moon_params = {
			"seed_value": moon_seed,
			"parent_planet": self,
			"distance": orbital_params[i].distance,
			"base_angle": orbital_params[i].base_angle,
			"orbit_speed": orbital_params[i].orbit_speed,
			"orbit_deviation": orbital_params[i].orbit_deviation,
			"phase_offset": orbital_params[i].phase_offset,
			"parent_name": planet_name,
			"use_texture_cache": use_texture_cache,
			"moon_type": moon_type,
			"is_gaseous": true  # Mark that this moon belongs to a gaseous planet
		}
		
		add_child(moon_instance)
		moon_instance.initialize(moon_params)
		moons.append(moon_instance)
	
	# Remaining moons have random types (up to total of 7)
	for m in range(3, num_moons):
		var moon_seed = seed_value + m * 100 + rng.randi() % 1000
		
		# Determine moon type based on position
		var moon_type = _get_moon_type_for_position(m, num_moons, rng)
		
		# Get the correct moon scene for this type
		if not _moon_scenes.has(moon_type):
			push_warning("Planet: Moon type not available: " + str(moon_type) + ", using ROCKY")
			moon_type = MoonType.ROCKY
			
		if not _moon_scenes.has(moon_type):
			push_error("Planet: No moon scenes available")
			continue
			
		var moon_scene = _moon_scenes[moon_type]
		if not moon_scene:
			continue
			
		var moon_instance = moon_scene.instantiate()
		if not moon_instance:
			continue
		
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
			"is_gaseous": true  # Mark that this moon belongs to a gaseous planet
		}
		
		add_child(moon_instance)
		moon_instance.initialize(moon_params)
		moons.append(moon_instance)
	
	# Emit signal that the planet has been loaded (after moons are created)
	emit_signal("planet_loaded", self)

# Return planet category
func get_category() -> int:
	return PlanetCategories.GASEOUS

# Return category name as string (for debugging/UI)
func get_category_name() -> String:
	return "Gaseous"
