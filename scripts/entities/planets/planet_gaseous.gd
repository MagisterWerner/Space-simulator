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
	# Gas giants have more moons
	max_moons = 5
	moon_chance = 100  # Always have moons
	min_moon_distance_factor = 2.0  # Moons orbit farther out
	max_moon_distance_factor = 2.8

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
func _get_moon_type_for_position(moon_position: int, _total_moons: int, _rng: RandomNumberGenerator) -> int:
	# Gas giants have specialized moon distribution
	# - Innermost moon (position=0): LAVA (volcanic due to tidal forces)
	# - Second moon (position=1): ROCKY
	# - Outer moons (position>=2): ICE (colder as they're further away)
	
	if moon_position == 0:
		return MoonType.LAVA
	elif moon_position == 1:
		return MoonType.ROCKY
	else:
		return MoonType.ICE

# Override for moon size scale - gas giant moons are 50% larger
func _get_moon_size_scale() -> float:
	return 2.0  # 100% larger moons for gaseous planets

# Override for orbit speed - gas giants have slower orbiting moons due to mass
func _get_orbit_speed_modifier() -> float:
	return 0.8  # 20% slower than terran planets

# Override to return appropriate planet type name
func _get_planet_type_name() -> String:
	return "Gas Giant"

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
