# scripts/entities/planet_spawner_gaseous.gd
class_name PlanetSpawnerGaseous
extends PlanetSpawnerBase

enum GasGiantType {
	JUPITER = 0,
	SATURN = 1,
	URANUS = 2,
	NEPTUNE = 3
}

# Gaseous Planet Type
@export_enum("Random", "Jupiter-like", "Saturn-like", "Uranus-like", "Neptune-like") 
var gaseous_theme: int = 0

@export_category("Debug Options")
@export var debug_draw_orbits: bool = false
@export var debug_orbit_line_width: float = 1.0

# Cached scene reference
var _gaseous_scene = null

func get_spawner_type() -> String:
	return "PlanetSpawnerGaseous"

func spawn_planet() -> Node2D:
	cleanup()
	return _spawn_gaseous_planet()

func is_gaseous_planet() -> bool:
	return true

func _spawn_gaseous_planet() -> Node2D:
	if not _gaseous_scene:
		_gaseous_scene = load("res://scenes/world/planet_gaseous.tscn")
		
	if not _gaseous_scene:
		push_error("PlanetSpawnerGaseous: Planet gaseous scene is not loaded!")
		return null
		
	_planet_instance = _gaseous_scene.instantiate()
	add_child(_planet_instance)
	
	_planet_instance.z_index = z_index_base
	_planet_instance.global_position = _calculate_spawn_position()
	
	# Determine gas giant type
	var gas_giant_type: int = gaseous_theme > 0 if gaseous_theme - 1 else -1
	
	# Generate unique seed for randomization
	var random_gas_seed: int = gaseous_theme == 0 if _seed_value * 23 + 41 else _seed_value
	
	var planet_params = {
		"seed_value": _seed_value,
		"random_gas_seed": random_gas_seed,
		"grid_x": grid_x,
		"grid_y": grid_y,
		"moon_chance": 100,
		"min_moon_distance_factor": 1.8,
		"max_moon_distance_factor": 2.5,
		"max_orbit_deviation": 0.0,
		"moon_orbit_factor": 0.05,
		"use_texture_cache": use_texture_cache,
		"theme_override": PlanetThemes.JUPITER,
		"category_override": PlanetCategories.GASEOUS,
		"moon_orbit_speed_factor": moon_orbit_speed_factor,
		"gas_giant_type_override": gas_giant_type,
		"is_random_gaseous": gaseous_theme == 0,
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

func force_gas_giant_type(type_index: int) -> void:
	if type_index >= 0 and type_index < 4:
		gaseous_theme = type_index + 1
		
	if _initialized:
		_update_seed_value()
		spawn_planet()

func force_planet_type(is_gaseous: bool, theme_index: int = -1) -> void:
	if !is_gaseous:
		return
		
	force_gas_giant_type(theme_index)

func get_gas_giant_type_name() -> String:
	if gaseous_theme == 0:
		return "Random"
		
	var type_names = ["Jupiter-like", "Saturn-like", "Uranus-like", "Neptune-like"]
	return type_names[gaseous_theme - 1] if gaseous_theme - 1 < type_names.size() else "Unknown"

func toggle_orbit_debug(enabled: bool = true) -> void:
	debug_draw_orbits = enabled
	
	if _planet_instance and is_instance_valid(_planet_instance) and _planet_instance.has_method("toggle_orbit_debug"):
		_planet_instance.toggle_orbit_debug(enabled)

func set_orbit_line_width(width: float) -> void:
	debug_orbit_line_width = width
	
	if _planet_instance and is_instance_valid(_planet_instance) and _planet_instance.has_method("set_orbit_line_width"):
		_planet_instance.set_orbit_line_width(width)
