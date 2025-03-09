# scripts/entities/planet_spawner_terran.gd
# Specialized spawner for terran planets
extends Node2D
class_name PlanetSpawnerTerran

# Import classification constants
const PlanetThemes = preload("res://scripts/generators/planet_generator_base.gd").PlanetTheme
const PlanetCategories = preload("res://scripts/generators/planet_generator_base.gd").PlanetCategory

signal planet_spawned(planet_instance)
signal spawner_ready

# Terran Planet Theme
@export_enum("Random", "Arid", "Ice", "Lava", "Lush", "Desert", "Alpine", "Ocean") 
var terran_theme: int = 0  # 0=Random, 1-7=Specific Terran theme

# Planet Configuration
@export_category("Planet Configuration")
@export var use_grid_position: bool = true
@export var grid_x: int = 0
@export var grid_y: int = 0
@export var local_seed_offset: int = 0  # Add to global seed for variation

# Planet properties
@export_category("Planet Properties")
@export var moon_chance: int = 40  # Lower chance of moons for terran planets
@export var planet_scale: float = 1.0
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

# Static texture cache
static var texture_cache = {
	"planets": {},
	"atmospheres": {},
	"moons": {}
}

func _init() -> void:
	# Override the base class properties with terran-specific defaults
	moon_chance = 40  # Lower chance of moons for terran planets
	planet_scale = 1.0  # Standard scale for terran planets

func _ready() -> void:
	# Connect to the main scene's GameSettings
	call_deferred("_find_game_settings")

func _find_game_settings() -> void:
	await get_tree().process_frame
	
	# Find GameSettings in the main scene
	var main_scene = get_tree().current_scene
	game_settings = main_scene.get_node_or_null("GameSettings")
	
	# Continue initialization
	_initialize()

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
		# Fallback when GameSettings isn't available
		_seed_value = hash(str(grid_x) + str(grid_y) + str(local_seed_offset) + str(Time.get_unix_time_from_system()))
	
	# Initialize RNG with our seed
	_rng.seed = _seed_value

# Override the spawner type method for debugging
func get_spawner_type() -> String:
	return "PlanetSpawnerTerran"

# Override the spawn_planet method to specifically spawn terran planets
func spawn_planet() -> Node2D:
	# Clean up any previously spawned planets
	cleanup()
	
	# Spawn a terran planet
	return _spawn_terran_planet()

# Implementation of is_terran_planet for API compatibility
func is_terran_planet() -> bool:
	return true

# Implementation of is_gaseous_planet for API compatibility
func is_gaseous_planet() -> bool:
	return false

# Spawn a terran planet with fixed parameters
func _spawn_terran_planet() -> Node2D:
	# Check if the planet scene is valid - load the terran planet scene
	var terran_scene = null
	if ResourceLoader.exists("res://scenes/world/planet_terran.tscn"):
		terran_scene = load("res://scenes/world/planet_terran.tscn")
	else:
		push_error("PlanetSpawnerTerran: Planet terran scene is not loaded!")
		return null
	
	# Create planet instance
	_planet_instance = terran_scene.instantiate()
	add_child(_planet_instance)
	
	# Set z-index for rendering order
	_planet_instance.z_index = z_index_base
	
	# Calculate position
	var spawn_position = _calculate_spawn_position()
	_planet_instance.global_position = spawn_position
	
	# Apply scale
	_planet_instance.scale = Vector2(planet_scale, planet_scale)
	
	# Determine terran theme (don't generate it here, let planet.gd decide if it's random)
	var theme_to_use: int = -1
	
	if terran_theme > 0:
		# User selected specific theme (subtract 1 because 0 is Random in the export enum)
		theme_to_use = terran_theme - 1
		
		# Verify it's a valid terran theme
		if theme_to_use >= PlanetThemes.GAS_GIANT:
			if game_settings and game_settings.debug_mode:
				print("PlanetSpawnerTerran: Invalid terran theme selected; reverting to random terran theme")
			theme_to_use = -1
	
	# Force-generate a random terran seed that will be used in planet.gd
	var random_terran_seed: int = _seed_value
	if terran_theme == 0:  # Random theme requested
		# Generate a unique seed for theme selection
		random_terran_seed = _seed_value * 17 + 31  # Prime multiplier to avoid patterns
	
	# Set up the planet parameters
	var planet_params = {
		"seed_value": _seed_value,
		"random_terran_seed": random_terran_seed,
		"grid_x": grid_x,
		"grid_y": grid_y,
		"moon_chance": moon_chance,
		"min_moon_distance_factor": 1.8,
		"max_moon_distance_factor": 2.5,
		"max_orbit_deviation": 0.15,
		"moon_orbit_factor": 0.05,
		"use_texture_cache": use_texture_cache,
		"theme_override": theme_to_use,
		"category_override": PlanetCategories.TERRAN,  # Force terran category
		"moon_orbit_speed_factor": moon_orbit_speed_factor,  # Pass the moon orbit speed factor
		"is_random_theme": terran_theme == 0,  # Flag indicating if we want a random theme
		"debug_planet_generation": debug_planet_generation
	}
	
	# If debug is enabled, add additional debug info to the parameters
	if debug_planet_generation:
		planet_params["debug_theme_source"] = "From terran_theme export: " + str(terran_theme)
	
	# Initialize the planet with our parameters
	_planet_instance.initialize(planet_params)
	
	# Register the planet with EntityManager if available
	_register_with_entity_manager(_planet_instance)
	
	# Connect to planet's loaded signal to handle moons if they spawn
	if _planet_instance.has_signal("planet_loaded"):
		if not _planet_instance.is_connected("planet_loaded", _on_planet_loaded):
			_planet_instance.connect("planet_loaded", _on_planet_loaded)
	
	# Emit spawned signal
	planet_spawned.emit(_planet_instance)
	
	# Debug output
	if game_settings and game_settings.debug_mode or debug_planet_generation:
		print("PlanetSpawnerTerran: Spawned terran planet at position ", _planet_instance.global_position)
		print("PlanetSpawnerTerran: Selected terran_theme=", terran_theme, " (0=Random, 1-7=specific)")
		if _planet_instance.has_method("get_theme_name"):
			print("PlanetSpawnerTerran: Actual theme used: ", _planet_instance.get_theme_name())
	
	# Check if texture cache needs cleaning
	_check_and_clean_cache()
	
	return _planet_instance

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

# Clean up the texture cache if it gets too large
static func _check_and_clean_cache() -> void:
	if texture_cache.planets.size() > 30:
		var keys = texture_cache.planets.keys()
		for i in range(10):  # Remove 1/3 of the cache
			if i < keys.size():
				texture_cache.planets.erase(keys[i])
				
	if texture_cache.atmospheres.size() > 30:
		var keys = texture_cache.atmospheres.keys()
		for i in range(10):
			if i < keys.size():
				texture_cache.atmospheres.erase(keys[i])
				
	if texture_cache.moons.size() > 30:
		var keys = texture_cache.moons.keys()
		for i in range(10):
			if i < keys.size():
				texture_cache.moons.erase(keys[i])

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

# Register the planet with EntityManager
func _register_with_entity_manager(planet_instance) -> void:
	# Register the planet with EntityManager if available
	if has_node("/root/EntityManager") and EntityManager.has_method("register_entity"):
		EntityManager.register_entity(planet_instance, "planet")

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

# Force a specific terran theme - Used for direct API calls
func force_terran_theme(theme_index: int) -> void:
	if theme_index >= 0 and theme_index < PlanetThemes.GAS_GIANT:
		terran_theme = theme_index + 1  # +1 because 0 is Random in the export enum
		
	# Update and respawn if already initialized
	if _initialized:
		_update_seed_value()
		spawn_planet()

# Override base class method for API compatibility
func force_planet_type(is_gaseous: bool, theme_index: int = -1) -> void:
	if is_gaseous:
		push_warning("PlanetSpawnerTerran: Cannot force gaseous planet type on a terran planet spawner")
		return
		
	force_terran_theme(theme_index)

# Public getter for the spawned planet instance
func get_planet_instance() -> Node2D:
	return _planet_instance

# Public getter for moon instances
func get_moon_instances() -> Array:
	return _moon_instances
