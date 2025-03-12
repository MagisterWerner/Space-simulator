# scripts/entities/planet_spawner_terran.gd
extends PlanetSpawnerBase
class_name PlanetSpawnerTerran

@export_enum("Random", "Arid", "Ice", "Lava", "Lush", "Desert", "Alpine", "Ocean") 
var terran_theme: int = 0

@export_category("Debug Options")
@export var debug_draw_orbits: bool = false
@export var debug_orbit_line_width: float = 1.0

# Cached scene reference
var _terran_scene = null

func get_spawner_type() -> String:
	return "PlanetSpawnerTerran"

func spawn_planet() -> Node2D:
	cleanup()
	return _spawn_terran_planet()

func is_terran_planet() -> bool:
	return true

func _spawn_terran_planet() -> Node2D:
	if not _terran_scene:
		if ResourceLoader.exists("res://scenes/world/planet_terran.tscn"):
			_terran_scene = load("res://scenes/world/planet_terran.tscn")
		else:
			push_error("PlanetSpawnerTerran: Planet terran scene is not loaded!")
			return null
	
	_planet_instance = _terran_scene.instantiate()
	add_child(_planet_instance)
	
	_planet_instance.z_index = z_index_base
	_planet_instance.global_position = _calculate_spawn_position()
	
	# Determine terran theme
	var theme_to_use: int = -1
	
	if terran_theme > 0:
		theme_to_use = terran_theme - 1
		if theme_to_use >= PlanetThemes.JUPITER:
			theme_to_use = -1
	
	# Generate unique seed for theme selection
	# FIX: Changed incompatible ternary operator to an if/else statement
	var random_terran_seed: int
	if terran_theme == 0:
		random_terran_seed = _seed_value * 17 + 31
	else:
		random_terran_seed = _seed_value
	
	var planet_params = {
		"seed_value": _seed_value,
		"random_terran_seed": random_terran_seed,
		"grid_x": grid_x,
		"grid_y": grid_y,
		"moon_chance": 40,
		"min_moon_distance_factor": 2.2,
		"max_moon_distance_factor": 3.0,
		"max_orbit_deviation": 0.15,
		"moon_orbit_factor": 0.05,
		"use_texture_cache": use_texture_cache,
		"theme_override": theme_to_use,
		"category_override": PlanetCategories.TERRAN,
		"moon_orbit_speed_factor": moon_orbit_speed_factor,
		"is_random_theme": terran_theme == 0,
		"debug_draw_orbits": debug_draw_orbits,
		"debug_orbit_line_width": debug_orbit_line_width,
		"debug_planet_generation": debug_planet_generation
	}
	
	_planet_instance.initialize(planet_params)
	_register_with_entity_manager(_planet_instance)
	
	if _planet_instance.has_signal("planet_loaded") and not _planet_instance.is_connected("planet_loaded", _on_planet_loaded):
		_planet_instance.connect("planet_loaded", _on_planet_loaded)
	
	planet_spawned.emit(_planet_instance)
	_check_and_clean_cache()
	
	return _planet_instance

func force_terran_theme(theme_index: int) -> void:
	if theme_index >= 0 and theme_index < PlanetThemes.JUPITER:
		terran_theme = theme_index + 1
		
	if _initialized:
		_update_seed_value()
		spawn_planet()

func toggle_orbit_debug(enabled: bool = true) -> void:
	debug_draw_orbits = enabled
	
	if _planet_instance and is_instance_valid(_planet_instance) and _planet_instance.has_method("toggle_orbit_debug"):
		_planet_instance.toggle_orbit_debug(enabled)

func set_orbit_line_width(width: float) -> void:
	debug_orbit_line_width = width
	
	if _planet_instance and is_instance_valid(_planet_instance) and _planet_instance.has_method("set_orbit_line_width"):
		_planet_instance.set_orbit_line_width(width)

func force_planet_type(is_gaseous: bool, theme_index: int = -1) -> void:
	if is_gaseous:
		return
		
	force_terran_theme(theme_index)
