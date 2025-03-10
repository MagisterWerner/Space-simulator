# scripts/entities/planets/planet_gaseous.gd
# Specialized implementation for gaseous planets (gas giants)
extends PlanetBase
class_name PlanetGaseous

# Gas giant type constants
enum GasGiantType {
	JUPITER = 0,  # Jupiter-like (beige/tan tones)
	SATURN = 1,   # Saturn-like (golden tones)
	URANUS = 2,   # Uranus-like (cyan/teal tones)
	NEPTUNE = 3   # Neptune-like (blue tones)
}

# Gaseous Planet Type
@export_enum("Random", "Jupiter-like", "Saturn-like", "Uranus-like", "Neptune-like") 
var gaseous_theme: int = 0  # 0=Random, 1-4=Specific Gaseous theme

# Note: We don't re-export debug options since they're already in the parent class
# Instead, we just access them directly when needed

func _init() -> void:
	# Fixed number of moons for all gaseous planets - must be at least 6 to fit 2 of each moon type
	max_moons = 6  # Increased from 7 to ensure we can fit 2 of each moon type (total of 6)
	moon_chance = 100  # Always have moons
	
	# Setup for non-intersecting orbits
	is_gaseous_planet = true
	
	# Update moon parameters for gas giants - make distance ranges more distinct with extra space
	_moon_params.distance_ranges[MoonType.VOLCANIC] = Vector2(1.6, 1.9)  # Closest to planet
	_moon_params.distance_ranges[MoonType.ROCKY] = Vector2(2.2, 2.5)     # Middle distance
	_moon_params.distance_ranges[MoonType.ICY] = Vector2(2.8, 3.3)       # Furthest from planet
	
	# Adjust speed modifiers for more noticeable differences
	_moon_params.speed_modifiers[MoonType.VOLCANIC] = 1.2   # Faster for close moons
	_moon_params.speed_modifiers[MoonType.ROCKY] = 1.0      # Normal speed
	_moon_params.speed_modifiers[MoonType.ICY] = 0.8        # Slower for distant moons

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
	
	# Get the variable pixel size for gaseous planets (based on seed)
	pixel_size = PlanetGeneratorBase.get_planet_size(seed_value, true)  # true = gaseous
	
	# Generate or get planet textures
	_generate_planet_texture()
	
	# Generate or get atmosphere textures
	_generate_atmosphere_texture()
	
	# Note: debug options are already set in the parent class's initialization

# Generate gas giant planet texture
func _generate_planet_texture() -> void:
	# Create a unique identifier that includes the theme and size
	var unique_identifier = str(seed_value) + "_theme_" + str(theme_id) + "_size_" + str(pixel_size)
	
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
	
	var unique_identifier = str(seed_value) + "_atmo_" + str(theme_id) + "_" + str(pixel_size)
	
	if use_texture_cache and PlanetGeneratorBase.texture_cache.has("atmospheres") and PlanetGeneratorBase.texture_cache.atmospheres.has(unique_identifier):
		# Use cached atmosphere texture
		atmosphere_texture = PlanetGeneratorBase.texture_cache.atmospheres[unique_identifier]
	else:
		# Generate new atmosphere texture - pass the pixel_size for accurate scaling
		atmosphere_texture = atmosphere_generator.generate_atmosphere_texture(
			theme_id, seed_value, atmosphere_data.color, atmosphere_data.thickness, pixel_size)
			
		# Cache the texture
		if use_texture_cache:
			if not PlanetGeneratorBase.texture_cache.has("atmospheres"):
				PlanetGeneratorBase.texture_cache["atmospheres"] = {}
			PlanetGeneratorBase.texture_cache.atmospheres[unique_identifier] = atmosphere_texture

# Override to determine appropriate moon types for gas giants with improved distribution
# Matches the function signature in the parent class
func _get_moon_type_for_position(_position: int) -> int:
	# For gaseous planets, we now have a guaranteed distribution
	var volcanic_threshold = 2  # First 2 positions are volcanic
	var rocky_threshold = 4     # Next 2 positions are rocky
	
	if _position < volcanic_threshold:
		return MoonType.VOLCANIC  # Innermost moons (closest to planet)
	elif _position < rocky_threshold:
		return MoonType.ROCKY     # Middle region moons
	else:
		return MoonType.ICY       # Outermost moons (furthest from planet)

# Override for orbit speed - gas giants have slower orbiting moons due to mass
func _get_orbit_speed_modifier() -> float:
	return 0.7  # 30% slower than terran planets (increased slowdown)

# Override to return appropriate planet type name
func _get_planet_type_name() -> String:
	return PlanetGeneratorBase.get_theme_name(theme_id)

# Override to return larger moon size scale for gas giants
func _get_moon_size_scale() -> float:
	return 1.2  # Gas giants have larger moons than terran planets

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
