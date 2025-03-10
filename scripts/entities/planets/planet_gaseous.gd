# scripts/entities/planets/planet_gaseous.gd
# Specialized implementation for gaseous planets (gas giants)
extends PlanetBase
class_name PlanetGaseous

func _init() -> void:
	# Fixed number of moons for all gaseous planets
	max_moons = 7  # Always use 7 moons
	moon_chance = 100  # Always have moons
	
	# Setup for non-intersecting orbits
	is_gaseous_planet = true
	
	# Redefine distance ranges for better visual separation
	volcanic_distance_range = Vector2(1.3, 1.6)  # Closest to planet
	rocky_distance_range = Vector2(1.9, 2.2)     # Middle distance
	icy_distance_range = Vector2(2.5, 3.0)       # Furthest from planet
	
	# Adjust speed modifiers for more noticeable differences
	volcanic_speed_modifier = 1.5   # Faster for close moons
	rocky_speed_modifier = 1.0      # Normal speed
	icy_speed_modifier = 0.6        # Slower for distant moons

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
	
	# Enable debug orbit visualization if requested in params
	if params.get("debug_draw_orbits", false):
		debug_draw_orbits = true
	
	# Set debug orbit line width if specified
	if params.has("debug_orbit_line_width"):
		debug_orbit_line_width = params.debug_orbit_line_width

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

# Override to determine appropriate moon types for gas giants with improved distribution
func _get_moon_type_for_position(moon_position: int, total_moons: int, rng: RandomNumberGenerator) -> int:
	# Distribute moon types consistently for better visual distinction:
	# Volcanic moons orbit closest to the planet
	# Icy moons orbit furthest from the planet
	# Rocky moons orbit in the middle regions
	
	# For gaseous planets, we want a clear hierarchy:
	var volcanic_threshold = int(total_moons * 0.3)  # 30% volcanic (closest)
	var rocky_threshold = int(total_moons * 0.7)     # 40% rocky (middle)
	
	if moon_position < volcanic_threshold:
		return MoonType.VOLCANIC  # Innermost moons (closest to planet)
	elif moon_position < rocky_threshold:
		return MoonType.ROCKY     # Middle region moons
	else:
		return MoonType.ICY       # Outermost moons (furthest from planet)

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

# Get gas giant type name - for debugging
func get_gas_giant_type_name() -> String:
	match theme_id:
		PlanetThemes.JUPITER: return "Jupiter-like"
		PlanetThemes.SATURN: return "Saturn-like"
		PlanetThemes.URANUS: return "Uranus-like"
		PlanetThemes.NEPTUNE: return "Neptune-like"
		_: return "Unknown Gas Giant Type"
