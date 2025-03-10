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
	
	# Setup for non-intersecting orbits
	is_gaseous_planet = true

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

# Return planet category
func get_category() -> int:
	return PlanetCategories.GASEOUS

# Return category name as string (for debugging/UI)
func get_category_name() -> String:
	return "Gaseous"
