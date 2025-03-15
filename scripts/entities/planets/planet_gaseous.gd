# scripts/entities/planets/planet_gaseous.gd
# Specialized implementation for gaseous planets (gas giants)
extends PlanetBase
class_name PlanetGaseous

# Gas giant type constants
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
	
	_moon_params.distance_ranges[MoonType.VOLCANIC] = Vector2(1.6, 1.9)
	_moon_params.distance_ranges[MoonType.ROCKY] = Vector2(2.2, 2.5)
	_moon_params.distance_ranges[MoonType.ICY] = Vector2(2.8, 3.3)
	
	_moon_params.speed_modifiers[MoonType.VOLCANIC] = 1.2
	_moon_params.speed_modifiers[MoonType.ROCKY] = 1.0
	_moon_params.speed_modifiers[MoonType.ICY] = 0.8

func _perform_specialized_initialization(params: Dictionary) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var theme_override = params.get("theme_override", -1)
	var gas_giant_type_override = params.get("gas_giant_type_override", -1)
	
	if gas_giant_type_override >= 0 and gas_giant_type_override < 4:
		theme_override = PlanetThemes.JUPITER + gas_giant_type_override
	
	if theme_override >= PlanetThemes.JUPITER and theme_override <= PlanetThemes.NEPTUNE:
		theme_id = theme_override
	else:
		theme_id = PlanetThemes.JUPITER + rng.randi() % 4
	
	pixel_size = PlanetGeneratorBase.get_planet_size(seed_value, true)
	
	_generate_planet_texture()
	_generate_atmosphere_texture()

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

func _generate_atmosphere_texture() -> void:
	var atmosphere_generator = AtmosphereGenerator.new()
	
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

func _get_moon_type_for_position(_position: int) -> int:
	var volcanic_threshold = 2
	var rocky_threshold = 4
	
	if _position < volcanic_threshold:
		return MoonType.VOLCANIC
	elif _position < rocky_threshold:
		return MoonType.ROCKY
	else:
		return MoonType.ICY

func _get_orbit_speed_modifier() -> float:
	return 0.7

func _get_planet_type_name() -> String:
	return PlanetGeneratorBase.get_theme_name(theme_id)

func _get_moon_size_scale() -> float:
	return 1.2

func get_category() -> int:
	return PlanetCategories.GASEOUS

func get_category_name() -> String:
	return "Gaseous"

func get_gas_giant_type_name() -> String:
	match theme_id:
		PlanetThemes.JUPITER: return "Jupiter-like"
		PlanetThemes.SATURN: return "Saturn-like"
		PlanetThemes.URANUS: return "Uranus-like"
		PlanetThemes.NEPTUNE: return "Neptune-like"
		_: return "Unknown Gas Giant Type"
