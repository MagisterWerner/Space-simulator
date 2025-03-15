# scripts/entities/planets/planet_terran.gd
# Specialized implementation for terran planets (rocky planets with solid surfaces)
extends PlanetBase
class_name PlanetTerran

var terran_subtype: String = ""

func _init() -> void:
	max_moons = 2
	moon_chance = 80
	is_gaseous_planet = false

func _perform_specialized_initialization(params: Dictionary) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var explicit_theme = params.get("theme_override", -1)
	
	if explicit_theme >= 0 and explicit_theme < PlanetThemes.JUPITER:
		theme_id = explicit_theme
	else:
		theme_id = rng.randi() % PlanetThemes.JUPITER
	
	pixel_size = PlanetGeneratorBase.get_planet_size(seed_value, false)
	terran_subtype = get_theme_name().to_lower()
	
	_generate_planet_texture()
	_generate_atmosphere_texture()

func _generate_planet_texture() -> void:
	var unique_identifier = str(seed_value) + "_terran_" + str(theme_id) + "_size_" + str(pixel_size)
	
	if use_texture_cache and PlanetGeneratorBase.texture_cache.has("terran") and PlanetGeneratorBase.texture_cache.terran.has(unique_identifier):
		planet_texture = PlanetGeneratorBase.texture_cache.terran[unique_identifier][0]
	else:
		var generator = PlanetGeneratorTerran.new()
		var textures = generator.create_planet_texture(seed_value, theme_id)
		planet_texture = textures[0]
		
		if use_texture_cache:
			if not PlanetGeneratorBase.texture_cache.has("terran"):
				PlanetGeneratorBase.texture_cache["terran"] = {}
			PlanetGeneratorBase.texture_cache.terran[unique_identifier] = textures

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

func _get_moon_type_for_position(_moon_position: int) -> int:
	return MoonType.ROCKY

func _get_orbit_speed_modifier() -> float:
	return 0.8

func _get_planet_type_name() -> String:
	if theme_id >= 0 and theme_id < PlanetThemes.JUPITER:
		return get_theme_name()
	return "Terran"

func get_category() -> int:
	return PlanetCategories.TERRAN

func get_category_name() -> String:
	return "Terran"
