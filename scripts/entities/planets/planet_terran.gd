# scripts/entities/planets/planet_terran.gd
# Specialized implementation for terran planets (rocky planets with solid surfaces)
extends PlanetBase
class_name PlanetTerran

# Additional terran-specific properties
var terran_subtype: String = ""  # Descriptive subtype (lush, desert, etc)

func _init() -> void:
	# Default max_moons value for terran planets is lower
	max_moons = 2
	moon_chance = 40  # 40% chance to have moons

# Override specialized initialization for terran planets
func _perform_specialized_initialization(params: Dictionary) -> void:
	# Create a local RNG for consistent random generation
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# Determine theme based on seed or override
	var explicit_theme = params.get("theme_override", -1)
	
	if explicit_theme >= 0 and explicit_theme < PlanetThemes.JUPITER:
		# Use the explicitly requested theme if it's a valid terran theme
		theme_id = explicit_theme
	else:
		# Generate a random terran theme
		theme_id = _determine_theme(seed_value)
	
	# Set the terran subtype for reference
	terran_subtype = get_theme_name().to_lower()
	
	# Generate or get planet textures
	_generate_planet_texture()
	
	# Generate or get atmosphere textures
	_generate_atmosphere_texture()
	
	# Set the pixel size for terran planets
	pixel_size = 256

# Determine theme based on seed - returns a valid terran theme
func _determine_theme(seed_val: int) -> int:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val
	
	# Generate a random terran theme (0 to JUPITER-1)
	return rng.randi() % PlanetThemes.JUPITER

# Generate planet textures
func _generate_planet_texture() -> void:
	var unique_identifier = str(seed_value) + "_terran_" + str(theme_id)
	
	if use_texture_cache and PlanetGeneratorBase.texture_cache.has("terran") and PlanetGeneratorBase.texture_cache.terran.has(unique_identifier):
		# Use cached texture
		var textures = PlanetGeneratorBase.texture_cache.terran[unique_identifier]
		planet_texture = textures[0]
	else:
		# Generate new texture
		var generator = PlanetGeneratorTerran.new()
		var textures = generator.create_planet_texture(seed_value, theme_id)
		planet_texture = textures[0]
		
		# Cache the texture
		if use_texture_cache:
			if not PlanetGeneratorBase.texture_cache.has("terran"):
				PlanetGeneratorBase.texture_cache["terran"] = {}
			PlanetGeneratorBase.texture_cache.terran[unique_identifier] = textures

# Generate atmosphere texture
func _generate_atmosphere_texture() -> void:
	var atmosphere_generator = AtmosphereGenerator.new()
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

# Override to determine appropriate moon types for terran planets
func _get_moon_type_for_position(_moon_position: int, _total_moons: int, _rng: RandomNumberGenerator) -> int:
	# All terran planets now only spawn rocky moons as requested
	return MoonType.ROCKY

# Override for orbit speed - terran planets have faster moon orbits
func _get_orbit_speed_modifier() -> float:
	return 1.0  # Standard speed for terran planets

# Override to return appropriate planet type name
func _get_planet_type_name() -> String:
	if theme_id >= 0 and theme_id < PlanetThemes.JUPITER:
		return get_theme_name()
	return "Terran"

# Return planet category
func get_category() -> int:
	return PlanetCategories.TERRAN

# Return category name as string (for debugging/UI)
func get_category_name() -> String:
	return "Terran"
