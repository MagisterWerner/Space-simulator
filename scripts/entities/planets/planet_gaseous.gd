# scripts/entities/planets/planet_gaseous.gd
extends PlanetBase
class_name PlanetGaseous

# Gas giant type enum 
enum GasGiantType {
	JUPITER = 0,
	SATURN = 1,
	URANUS = 2,
	NEPTUNE = 3
}

@export_enum("Random", "Jupiter-like", "Saturn-like", "Uranus-like", "Neptune-like") 
var gaseous_theme: int = 0

func _init() -> void:
	max_moons = 6
	moon_chance = 100
	is_gaseous_planet = true
	
	# Configure moon orbit distances for gas giants
	_moon_params.distance_ranges[MoonType.VOLCANIC] = Vector2(1.6, 1.9)
	_moon_params.distance_ranges[MoonType.ROCKY] = Vector2(2.2, 2.5)
	_moon_params.distance_ranges[MoonType.ICY] = Vector2(2.8, 3.3)
	
	# Configure moon orbit speeds
	_moon_params.speed_modifiers[MoonType.VOLCANIC] = 1.2
	_moon_params.speed_modifiers[MoonType.ROCKY] = 1.0
	_moon_params.speed_modifiers[MoonType.ICY] = 0.8

# Override to generate texture for gaseous planets
func _generate_planet_texture() -> void:
	var unique_identifier = str(seed_value) + "_theme_" + str(theme_id) + "_size_" + str(pixel_size)
	
	if use_texture_cache and PlanetGeneratorBase.texture_cache.has("gaseous") and PlanetGeneratorBase.texture_cache.gaseous.has(unique_identifier):
		planet_texture = PlanetGeneratorBase.texture_cache.gaseous[unique_identifier][0]
	else:
		var generator = PlanetGeneratorGaseous.new()
		var textures = generator.create_planet_texture(seed_value, theme_id)
		planet_texture = textures[0]
		
		if use_texture_cache:
			if not PlanetGeneratorBase.texture_cache.has("gaseous"):
				PlanetGeneratorBase.texture_cache["gaseous"] = {}
			PlanetGeneratorBase.texture_cache.gaseous[unique_identifier] = textures

# Override to generate atmosphere for gaseous planets
func _generate_atmosphere_texture() -> void:
	var atmosphere_generator = AtmosphereGenerator.new()
	
	# Create atmosphere data if not provided
	if atmosphere_data.is_empty():
		atmosphere_data = atmosphere_generator.generate_atmosphere_data(theme_id, seed_value)
	
	var unique_identifier = str(seed_value) + "_atmo_" + str(theme_id) + "_" + str(pixel_size)
	
	if use_texture_cache and PlanetGeneratorBase.texture_cache.has("atmospheres") and PlanetGeneratorBase.texture_cache.atmospheres.has(unique_identifier):
		atmosphere_texture = PlanetGeneratorBase.texture_cache.atmospheres[unique_identifier]
	else:
		atmosphere_texture = atmosphere_generator.generate_atmosphere_texture(
			theme_id, seed_value, atmosphere_data.color, atmosphere_data.thickness, pixel_size)
			
		if use_texture_cache:
			if not PlanetGeneratorBase.texture_cache.has("atmospheres"):
				PlanetGeneratorBase.texture_cache["atmospheres"] = {}
			PlanetGeneratorBase.texture_cache.atmospheres[unique_identifier] = atmosphere_texture

# Get planet category
func get_category() -> int:
	return PlanetCategories.GASEOUS

# Get category name
func get_category_name() -> String:
	return "Gaseous"

# Get gas giant type name
func get_gas_giant_type_name() -> String:
	match theme_id:
		PlanetThemes.JUPITER: return "Jupiter-like"
		PlanetThemes.SATURN: return "Saturn-like"
		PlanetThemes.URANUS: return "Uranus-like"
		PlanetThemes.NEPTUNE: return "Neptune-like"
		_: return "Unknown Gas Giant Type"
