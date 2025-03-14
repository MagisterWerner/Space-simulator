# scripts/entities/planets/planet_terran.gd
extends PlanetBase
class_name PlanetTerran

var terran_subtype: String = ""

func _init() -> void:
	max_moons = 2
	moon_chance = 80
	is_gaseous_planet = false

# Override to generate texture for terran planets
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

# Override to generate atmosphere for terran planets
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
	return PlanetCategories.TERRAN

# Get category name
func get_category_name() -> String:
	return "Terran"
