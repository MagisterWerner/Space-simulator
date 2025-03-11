# scripts/entities/planet_spawner_base.gd
# Base class for planet spawners that contains common functionality
class_name PlanetSpawnerBase
extends Node2D

# Import classification constants
const PlanetThemes = preload("res://scripts/generators/planet_generator_base.gd").PlanetTheme
const PlanetCategories = preload("res://scripts/generators/planet_generator_base.gd").PlanetCategory

@warning_ignore("unused_signal")
signal planet_spawned(planet_instance)
signal spawner_ready

# Planet Configuration
@export_category("Planet Configuration")
@export var use_grid_position: bool = true
@export var grid_x: int = 0
@export var grid_y: int = 0
@export var local_seed_offset: int = 0  # Add to global seed for variation

# Moon properties
@export_category("Moon Properties")
@export var moon_orbit_speed_factor: float = 1.0  # Multiplier for moon orbit speed

@export_category("Performance Options")
@export var use_texture_cache: bool = true
@export var pregenerate: bool = true

@export_category("Rendering")
@export var z_index_base: int = -10  # Base z-index for planets

@export_category("Debug")
@export var debug_planet_generation: bool = false

# Internal variables
var _seed_value: int = 0
var _planet_instance = null
var _moon_instances = []
var _initialized: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var game_settings: GameSettings = null

# Modified: Using load instead of preload to avoid missing file errors
var planet_scene = null

# IMPORTANT: Shared texture cache that will be used by all planet spawner types
# This replaces the original PlanetSpawner.texture_cache
static var texture_cache = {
	"planets": {},
	"atmospheres": {},
	"moons": {}
}

# Cache size control - using a static variable for all spawners
static var cache_cleanup_counter: int = 0
const MAX_CACHE_SIZE = 30

func _ready() -> void:
	# Connect to SeedManager for seed changes
	if has_node("/root/SeedManager"):
		if SeedManager.has_signal("seed_changed") and not SeedManager.is_connected("seed_changed", _on_seed_changed):
			SeedManager.connect("seed_changed", _on_seed_changed)
	
	# Connect to the main scene's GameSettings
	call_deferred("_find_game_settings")

func _find_game_settings() -> void:
	await get_tree().process_frame
	
	# Find GameSettings in the main scene
	var main_scene = get_tree().current_scene
	game_settings = main_scene.get_node_or_null("GameSettings")
	
	# Connect to GameSettings seed changes
	if game_settings and game_settings.has_signal("seed_changed") and not game_settings.is_connected("seed_changed", _on_seed_changed):
		game_settings.connect("seed_changed", _on_seed_changed)
	
	# Continue initialization
	_initialize()

# Handle seed changes
func _on_seed_changed(_new_seed: int) -> void:
	if game_settings and game_settings.debug_mode:
		print("%s: Detected seed change, updating..." % get_spawner_type())
	
	# Update seed value
	_update_seed_value()
	
	# Regenerate the planet
	if _initialized:
		spawn_planet()

func _initialize() -> void:
	if _initialized:
		return
	
	# Initialize seed value
	_update_seed_value()
	
	# Always spawn planet immediately
	spawn_planet()
	
	_initialized = true
	spawner_ready.emit()
	
	# Debug output
	if game_settings and game_settings.debug_mode:
		print("%s: Initialized at grid position (%d, %d) with seed: %d" % 
			  [get_spawner_type(), grid_x, grid_y, _seed_value])

func _update_seed_value() -> void:
	if game_settings:
		# Get base seed from GameSettings
		var base_seed = game_settings.get_seed()
		
		# Add grid position to create unique seeds per cell
		if use_grid_position:
			_seed_value = base_seed + (grid_x * 1000) + (grid_y * 100) + local_seed_offset
		else:
			# Use position-based seed if not using grid
			var pos_hash = (int(global_position.x) * 13) + (int(global_position.y) * 7)
			_seed_value = base_seed + pos_hash + local_seed_offset
	else:
		# Fallback when GameSettings isn't available - use SeedManager if possible
		if has_node("/root/SeedManager"):
			_seed_value = SeedManager.get_seed() + (grid_x * 1000) + (grid_y * 100) + local_seed_offset
		else:
			# Last resort fallback
			_seed_value = hash(str(grid_x) + str(grid_y) + str(local_seed_offset) + str(Time.get_unix_time_from_system()))
	
	# Initialize RNG with our seed
	_rng.seed = _seed_value
	
	if game_settings and game_settings.debug_mode:
		print("%s: Generated seed %d for grid position (%d, %d)" % [get_spawner_type(), _seed_value, grid_x, grid_y])

# This is a virtual method that derived classes will override
func spawn_planet() -> Node2D:
	push_error("PlanetSpawnerBase: spawn_planet is a virtual method that should be overridden")
	return null

# Return the type name for use in debug prints - doesn't override native method
func get_spawner_type() -> String:
	return "PlanetSpawnerBase"

# Handle connection to planet instance
func _on_planet_loaded(planet) -> void:
	# Access moons that were created by the planet
	if planet and is_instance_valid(planet) and planet.moons.size() > 0:
		for moon in planet.moons:
			if is_instance_valid(moon):
				_moon_instances.append(moon)
				
				# Register each moon with EntityManager
				if has_node("/root/EntityManager"):
					EntityManager.register_entity(moon, "moon")
				
				if game_settings and game_settings.debug_mode:
					print("Moon registered: ", moon.moon_name)

# Clean up existing planet and moons
func cleanup() -> void:
	# Clean up existing planet and moons
	if _planet_instance and is_instance_valid(_planet_instance):
		# Disconnect signal to avoid issues
		if _planet_instance.has_signal("planet_loaded"):
			if _planet_instance.is_connected("planet_loaded", _on_planet_loaded):
				_planet_instance.disconnect("planet_loaded", _on_planet_loaded)
		
		# Deregister from EntityManager
		if has_node("/root/EntityManager"):
			EntityManager.deregister_entity(_planet_instance)
		
		_planet_instance.queue_free()
		_planet_instance = null
	
	# Clear moon references
	_moon_instances.clear()

# Set grid position and update
func set_grid_position(x: int, y: int) -> void:
	grid_x = x
	grid_y = y
	_update_seed_value()
	
	# Update position if using grid
	if use_grid_position and _planet_instance and is_instance_valid(_planet_instance):
		var new_pos
		
		if game_settings:
			new_pos = game_settings.get_cell_world_position(Vector2i(grid_x, grid_y))
		elif has_node("/root/GridManager"):
			new_pos = GridManager.cell_to_world(Vector2i(grid_x, grid_y))
		else:
			return
			
		_planet_instance.global_position = new_pos
		
		if game_settings and game_settings.debug_mode:
			print("%s: Updated position to grid (%d, %d)" % [get_spawner_type(), grid_x, grid_y])

# Common method to calculate position for the planet
func _calculate_spawn_position() -> Vector2:
	var spawn_position = Vector2.ZERO
	if use_grid_position:
		# Use GameSettings or GridManager to get the cell position
		if game_settings:
			spawn_position = game_settings.get_cell_world_position(Vector2i(grid_x, grid_y))
		elif has_node("/root/GridManager"):
			spawn_position = GridManager.cell_to_world(Vector2i(grid_x, grid_y))
	else:
		spawn_position = global_position
	
	return spawn_position

# Get a deterministic parameter for the planet from seed
func get_deterministic_param(param_name: String, min_val: float, max_val: float, sub_id: int = 0) -> float:
	# Always try to use SeedManager first for consistency
	if has_node("/root/SeedManager"):
		# Create a deterministic object ID from param_name
		var object_id = _seed_value + hash(param_name)
		return SeedManager.get_random_value(object_id, min_val, max_val, sub_id)
	elif game_settings:
		# Fallback to GameSettings
		var object_id = _seed_value + hash(param_name)
		return game_settings.get_random_value(object_id, min_val, max_val, sub_id)
	else:
		# Local fallback
		return min_val + (max_val - min_val) * _rng.randf()

# Public getter for the spawned planet instance
func get_planet_instance() -> Node2D:
	return _planet_instance

# Public getter for moon instances
func get_moon_instances() -> Array:
	return _moon_instances

# Register the planet with EntityManager
func _register_with_entity_manager(planet_instance) -> void:
	# Register the planet with EntityManager if available
	if has_node("/root/EntityManager") and EntityManager.has_method("register_entity"):
		EntityManager.register_entity(planet_instance, "planet")

# Clean up the texture cache if it gets too large
static func _check_and_clean_cache() -> void:
	cache_cleanup_counter += 1
	
	# Only check every 5 spawns to avoid performance impact
	if cache_cleanup_counter % 5 != 0:
		return
	
	if texture_cache.planets.size() > MAX_CACHE_SIZE:
		var keys = texture_cache.planets.keys()
		for i in range(int(float(MAX_CACHE_SIZE) / 3.0)):  # Remove 1/3 of the cache - Fixed integer division
			if i < keys.size():
				texture_cache.planets.erase(keys[i])
				
	if texture_cache.atmospheres.size() > MAX_CACHE_SIZE:
		var keys = texture_cache.atmospheres.keys()
		for i in range(int(float(MAX_CACHE_SIZE) / 3.0)):  # Fixed integer division
			if i < keys.size():
				texture_cache.atmospheres.erase(keys[i])
				
	if texture_cache.moons.size() > MAX_CACHE_SIZE:
		var keys = texture_cache.moons.keys()
		for i in range(int(float(MAX_CACHE_SIZE) / 3.0)):  # Fixed integer division
			if i < keys.size():
				texture_cache.moons.erase(keys[i])

# [NEW] Static method to clear the entire texture cache when the seed changes
static func clear_texture_cache() -> void:
	texture_cache = {
		"planets": {},
		"atmospheres": {},
		"moons": {}
	}
	cache_cleanup_counter = 0
	print("PlanetSpawnerBase: Texture cache cleared due to seed change")

# The following methods ensure compatibility with the original PlanetSpawner API

# Check if planet is gaseous (for API compatibility)
func is_gaseous_planet() -> bool:
	return false

# Check if planet is terran (for API compatibility)
func is_terran_planet() -> bool:
	return false

# Force a specific planet type - base implementation does nothing
func force_planet_type(_is_gaseous: bool, _theme_index: int = -1) -> void:
	push_warning("%s: force_planet_type is not implemented in the base class" % get_spawner_type())
