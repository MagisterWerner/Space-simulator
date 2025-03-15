extends Node2D
class_name PlanetSpawnerBase

const PlanetThemes = preload("res://scripts/generators/planet_generator_base.gd").PlanetTheme
const PlanetCategories = preload("res://scripts/generators/planet_generator_base.gd").PlanetCategory

# FIX: Using this signal in the spawn_planet() method
signal planet_spawned(planet_instance)
signal spawner_ready

# Planet Configuration
@export_category("Planet Configuration")
@export var use_grid_position: bool = true
@export var grid_x: int = 0
@export var grid_y: int = 0
@export var local_seed_offset: int = 0

# Moon properties
@export_category("Moon Properties")
@export var moon_orbit_speed_factor: float = 1.0

@export_category("Performance Options")
@export var use_texture_cache: bool = true
@export var pregenerate: bool = true

@export_category("Rendering")
@export var z_index_base: int = -10

@export_category("Debug")
@export var debug_planet_generation: bool = false

# Cached references
var _seed_manager = null
var _entity_manager = null
var _grid_manager = null

# Internal variables
var _seed_value: int = 0
var _planet_instance = null
var _moon_instances = []
var _initialized: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var game_settings = null

# Shared texture cache for all planet spawner types - with proper cache management
static var texture_cache = {
	"planets": {},
	"atmospheres": {},
	"moons": {}
}

static var cache_cleanup_counter: int = 0
const MAX_CACHE_SIZE = 30
const MAX_CACHE_ENTRIES_TO_REMOVE = 10

func _ready() -> void:
	_cache_singletons()
	call_deferred("_find_game_settings")
	add_to_group("planet_spawners")

func _cache_singletons() -> void:
	_seed_manager = get_node_or_null("/root/SeedManager")
	_entity_manager = get_node_or_null("/root/EntityManager")
	_grid_manager = get_node_or_null("/root/GridManager")
	
	if _seed_manager and _seed_manager.has_signal("seed_changed"):
		_seed_manager.connect("seed_changed", _on_seed_changed)

func _find_game_settings() -> void:
	await get_tree().process_frame
	
	game_settings = get_tree().current_scene.get_node_or_null("GameSettings")
	
	if game_settings and game_settings.has_signal("seed_changed"):
		game_settings.connect("seed_changed", _on_seed_changed)
	
	_initialize()

func _on_seed_changed(_new_seed: int) -> void:
	_update_seed_value()
	
	if _initialized:
		spawn_planet()

func _initialize() -> void:
	if _initialized:
		return
	
	_update_seed_value()
	spawn_planet()
	_initialized = true
	spawner_ready.emit()

func _update_seed_value() -> void:
	var base_seed: int
	
	if game_settings:
		base_seed = game_settings.get_seed()
	elif _seed_manager:
		base_seed = _seed_manager.get_seed()
	else:
		base_seed = int(Time.get_unix_time_from_system())
	
	if use_grid_position:
		# Deterministic seed based on grid position and offset
		_seed_value = base_seed + (grid_x * 1000) + (grid_y * 100) + local_seed_offset
	else:
		# Deterministic seed based on position hash and offset
		var pos_hash = (int(global_position.x) * 13) + (int(global_position.y) * 7)
		_seed_value = base_seed + pos_hash + local_seed_offset
	
	_rng.seed = _seed_value
	
	if debug_planet_generation and _initialized:
		print("PlanetSpawner: Seed updated to ", _seed_value)

func spawn_planet() -> Node2D:
	# FIX: Using the planet_spawned signal in this base method
	var planet = _create_default_planet()
	planet_spawned.emit(planet)
	return planet

func _create_default_planet() -> Node2D:
	# Simple default implementation that creates a placeholder planet
	var placeholder = Node2D.new()
	placeholder.name = "PlaceholderPlanet"
	add_child(placeholder)
	_planet_instance = placeholder
	return placeholder

func get_spawner_type() -> String:
	return "PlanetSpawnerBase"

func _on_planet_loaded(planet) -> void:
	if not planet or not is_instance_valid(planet) or planet.moons.size() == 0:
		return
		
	for moon in planet.moons:
		if is_instance_valid(moon):
			_moon_instances.append(moon)
			
			if _entity_manager:
				_entity_manager.register_entity(moon, "moon")

func cleanup() -> void:
	if _planet_instance and is_instance_valid(_planet_instance):
		if _planet_instance.has_signal("planet_loaded") and _planet_instance.is_connected("planet_loaded", _on_planet_loaded):
			_planet_instance.disconnect("planet_loaded", _on_planet_loaded)
		
		if _entity_manager:
			_entity_manager.deregister_entity(_planet_instance)
		
		_planet_instance.queue_free()
		_planet_instance = null
	
	_moon_instances.clear()

func set_grid_position(x: int, y: int) -> void:
	grid_x = x
	grid_y = y
	_update_seed_value()
	
	if not use_grid_position or not _planet_instance or not is_instance_valid(_planet_instance):
		return
		
	var new_pos: Vector2
	
	if game_settings:
		new_pos = game_settings.get_cell_world_position(Vector2i(grid_x, grid_y))
	elif _grid_manager:
		new_pos = _grid_manager.cell_to_world(Vector2i(grid_x, grid_y))
	else:
		return
		
	_planet_instance.global_position = new_pos

func _calculate_spawn_position() -> Vector2:
	if use_grid_position:
		if game_settings:
			return game_settings.get_cell_world_position(Vector2i(grid_x, grid_y))
		elif _grid_manager:
			return _grid_manager.cell_to_world(Vector2i(grid_x, grid_y))
	
	return global_position

func get_deterministic_param(param_name: String, min_val: float, max_val: float, sub_id: int = 0) -> float:
	# Create a deterministic parameter ID
	var param_id = hash(param_name) + sub_id
	
	if _seed_manager:
		var object_id = _seed_value + param_id
		return _seed_manager.get_random_value(object_id, min_val, max_val, 0)
	elif game_settings:
		var object_id = _seed_value + param_id
		return game_settings.get_random_value(object_id, min_val, max_val, 0)
	
	# Fallback to local RNG with consistent seed
	var local_rng = RandomNumberGenerator.new()
	local_rng.seed = _seed_value + param_id
	return min_val + (max_val - min_val) * local_rng.randf()

func get_planet_instance() -> Node2D:
	return _planet_instance

func get_moon_instances() -> Array:
	return _moon_instances

func _register_with_entity_manager(planet_instance) -> void:
	if _entity_manager:
		_entity_manager.register_entity(planet_instance, "planet")

static func _check_and_clean_cache() -> void:
	cache_cleanup_counter += 1
	
	if cache_cleanup_counter % 5 != 0:
		return
	
	for cache_type in ["planets", "atmospheres", "moons"]:
		if texture_cache[cache_type].size() > MAX_CACHE_SIZE:
			var keys = texture_cache[cache_type].keys()
			# Use deterministic cleanup - always remove the first entries
			for i in range(min(MAX_CACHE_ENTRIES_TO_REMOVE, keys.size())):
				texture_cache[cache_type].erase(keys[i])

static func clear_texture_cache() -> void:
	texture_cache = {
		"planets": {},
		"atmospheres": {},
		"moons": {}
	}
	cache_cleanup_counter = 0
	print("PlanetSpawnerBase: Texture cache cleared")

# API compatibility methods
func is_gaseous_planet() -> bool:
	return false

func is_terran_planet() -> bool:
	return false

func force_planet_type(_is_gaseous: bool, _theme_index: int = -1) -> void:
	pass
