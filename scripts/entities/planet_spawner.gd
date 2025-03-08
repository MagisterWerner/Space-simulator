# scripts/entities/planet_spawner.gd
# ==========================
# An advanced planet spawner that enables procedural planet generation
# with extensive configuration options. Designed to work with the grid system
# for easy procedural world generation.
extends Node2D
class_name PlanetSpawner

# Import planet classification constants
const PlanetThemes = preload("res://scripts/generators/planet_generator.gd").PlanetTheme
const PlanetCategories = preload("res://scripts/generators/planet_generator.gd").PlanetCategory

## Signals
signal planet_spawned(planet_instance, grid_coords)
signal spawner_ready
signal planet_generation_started(params)
signal planet_generation_completed(planet)

# Planet Type Selection
@export_category("Default Planet Configuration")
@export_enum("Terran", "Gaseous") var default_planet_category: int = 0  # 0=Terran, 1=Gaseous

# Terran Planet Theme (only used when planet_category is Terran)
@export_enum("Random", "Arid", "Ice", "Lava", "Lush", "Desert", "Alpine", "Ocean") 
var default_terran_theme: int = 0  # 0=Random, 1-7=Specific Terran theme

# Random Seed Option 
@export var force_random_seed: bool = false  # When true, ignores grid positioning

# Planet Configuration
@export_category("Planet Configuration")
@export var planet_scene: PackedScene = preload("res://scenes/world/planet.tscn")
@export var use_grid_position: bool = true
@export var grid_x: int = 0
@export var grid_y: int = 0
@export var local_seed_offset: int = 0  # Add to global seed for variation

# Planet properties
@export_category("Planet Properties")
@export var moon_chance: int = 50 # Percentage chance for terran planets to spawn moons
@export var planet_scale: float = 1.0
@export var moon_orbit_speed_factor: float = 1.0  # Multiplier for moon orbit speed

@export_category("Performance Options")
@export var use_texture_cache: bool = true
@export var pregenerate: bool = true

@export_category("Rendering")
@export var z_index_base: int = -10  # Base z-index for planets

@export_category("Debug")
@export var debug_mode: bool = false

# Internal variables
var _seed_value: int = 0
var _planet_instance = null
var _moon_instances = []
var _initialized: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _world_grid = null  # Reference to the world grid

# Texture cache shared between all planet spawners
static var texture_cache = {
	"planets": {},
	"atmospheres": {},
	"moons": {}
}

# Cache size control
const MAX_CACHE_SIZE = 30
var _cache_last_cleaned = 0

# String-to-enum mappings for planet types
const CATEGORY_MAP = {
	"terran": PlanetCategories.TERRAN,
	"gaseous": PlanetCategories.GASEOUS
}

const THEME_MAP = {
	"arid": PlanetThemes.ARID,
	"ice": PlanetThemes.ICE,
	"lava": PlanetThemes.LAVA,
	"lush": PlanetThemes.LUSH,
	"desert": PlanetThemes.DESERT,
	"alpine": PlanetThemes.ALPINE,
	"ocean": PlanetThemes.OCEAN,
	"gas_giant": PlanetThemes.GAS_GIANT
}

# Reverse mappings (enum to string) for easier API usage
const CATEGORY_NAMES = {
	PlanetCategories.TERRAN: "terran",
	PlanetCategories.GASEOUS: "gaseous"
}

const THEME_NAMES = {
	PlanetThemes.ARID: "arid",
	PlanetThemes.ICE: "ice",
	PlanetThemes.LAVA: "lava",
	PlanetThemes.LUSH: "lush",
	PlanetThemes.DESERT: "desert",
	PlanetThemes.ALPINE: "alpine",
	PlanetThemes.OCEAN: "ocean",
	PlanetThemes.GAS_GIANT: "gas_giant"
}

func _ready() -> void:
	# Connect to SeedManager signal if available
	if has_node("/root/SeedManager") and SeedManager.has_signal("seed_changed"):
		SeedManager.seed_changed.connect(_on_seed_changed)
	
	# Initialize after a frame to ensure autoloads are ready
	call_deferred("_initialize")

func _initialize() -> void:
	if _initialized:
		return
	
	# Find the world grid
	_find_world_grid()
	
	# Initialize seed value
	_update_seed_value()
	
	_initialized = true
	spawner_ready.emit()
	
	if debug_mode:
		print("PlanetSpawner initialized with seed: ", _seed_value)

# Find and store a reference to the world grid
func _find_world_grid() -> void:
	# Try to find the world grid
	var grids = get_tree().get_nodes_in_group("world_grid")
	if not grids.is_empty():
		_world_grid = grids[0]
		if debug_mode:
			print("PlanetSpawner: Found world grid at ", _world_grid.get_path())
	else:
		# Try to find in Main scene
		var main = get_node_or_null("/root/Main")
		if main:
			_world_grid = main.get_node_or_null("WorldGrid")
			if _world_grid and debug_mode:
				print("PlanetSpawner: Found world grid in Main scene")

# PUBLIC API

## Spawn a planet with specific category and theme (as strings)
## Returns the created planet instance
## Example: spawn_specific_planet("terran", "lush")
func spawn_specific_planet(category_name: String = "random", theme_name: String = "random", at_position: Vector2 = Vector2.ZERO) -> Node2D:
	# Determine category enum value
	var category_enum: int
	if category_name == "random":
		category_enum = default_planet_category  # Use exported value
	else:
		category_name = category_name.to_lower()
		category_enum = CATEGORY_MAP.get(category_name, default_planet_category)
	
	# Determine theme enum value
	var theme_enum: int = -1  # -1 means random
	if theme_name != "random":
		theme_name = theme_name.to_lower()
		theme_enum = THEME_MAP.get(theme_name, -1)
	
	# Special case for gaseous planets (only gas_giant theme available)
	if category_enum == PlanetCategories.GASEOUS:
		theme_enum = PlanetThemes.GAS_GIANT
	
	# Create detailed parameters
	var params = {
		"planet_category": category_enum,
		"planet_theme": theme_enum,
		"position": at_position
	}
	
	# Spawn the planet with parameters
	return spawn_planet_with_params(params)

## Convenient method to spawn a terran planet with specific theme
func spawn_terran_planet(theme_name: String = "random", at_position: Vector2 = Vector2.ZERO) -> Node2D:
	return spawn_specific_planet("terran", theme_name, at_position)

## Convenient method to spawn a gaseous planet
func spawn_gaseous_planet(at_position: Vector2 = Vector2.ZERO) -> Node2D:
	return spawn_specific_planet("gaseous", "random", at_position)

## Spawn a planet at a specific grid position
func spawn_planet_at_grid_position(grid_coords: Vector2i, category_name: String = "random", theme_name: String = "random") -> Node2D:
	# Get world position from grid
	var world_position = Vector2.ZERO
	
	if has_node("/root/GridManager"):
		world_position = GridManager.cell_to_world(grid_coords)
	elif _world_grid != null:
		# Use the stored reference to the world grid
		if _world_grid.has_method("get_cell_center"):
			world_position = _world_grid.get_cell_center(grid_coords)
	
	# Set grid position for tracking
	grid_x = grid_coords.x
	grid_y = grid_coords.y
	
	# Update seed based on grid position
	_update_seed_value()
	
	# Spawn the planet
	var planet = spawn_specific_planet(category_name, theme_name, world_position)
	
	# Update grid data if possible
	if _world_grid != null:
		if _world_grid.has_method("set_cell_content"):
			var content_type = "planet_" + category_name.to_lower()
			_world_grid.set_cell_content(grid_coords, content_type, planet)
	
	# Emit signal with grid coordinates
	planet_spawned.emit(planet, grid_coords)
	
	return planet

## Spawn a planet with a complete parameter dictionary
func spawn_planet_with_params(params: Dictionary) -> Node2D:
	# Clean up any previously spawned planets
	cleanup()
	
	# Extract parameters with defaults
	var category = params.get("planet_category", default_planet_category)
	var theme = params.get("planet_theme", -1)  # -1 = random
	var world_position = params.get("position", global_position)
	var custom_scale = params.get("planet_scale", planet_scale)
	var custom_moon_chance = params.get("moon_chance", moon_chance)
	var custom_moon_orbit_factor = params.get("moon_orbit_speed_factor", moon_orbit_speed_factor)
	var custom_z_index = params.get("z_index", z_index_base)
	
	# Signal that generation has started
	planet_generation_started.emit(params)
	
	# Create planet instance
	_planet_instance = planet_scene.instantiate()
	add_child(_planet_instance)
	
	# Set position and scale
	_planet_instance.global_position = world_position
	_planet_instance.scale = Vector2(custom_scale, custom_scale)
	_planet_instance.z_index = custom_z_index
	
	# Create complete planet params
	var planet_params = {
		"seed_value": _seed_value,
		"grid_x": grid_x,
		"grid_y": grid_y,
		"moon_chance": custom_moon_chance,
		"min_moon_distance_factor": params.get("min_moon_distance_factor", 1.8),
		"max_moon_distance_factor": params.get("max_moon_distance_factor", 2.5),
		"max_orbit_deviation": params.get("max_orbit_deviation", 0.15),
		"moon_orbit_factor": params.get("moon_orbit_factor", 0.05),
		"use_texture_cache": params.get("use_texture_cache", use_texture_cache),
		"theme_override": theme,
		"category_override": category,
		"moon_orbit_speed_factor": custom_moon_orbit_factor
	}
	
	# Add any custom moon parameters if provided
	if params.has("moons"):
		planet_params["custom_moons"] = params["moons"]
	
	# Initialize the planet with our parameters
	_planet_instance.initialize(planet_params)
	
	# Register the planet with EntityManager if available
	if has_node("/root/EntityManager"):
		EntityManager.register_entity(_planet_instance, "planet")
	
	# Connect to planet's loaded signal to handle moons if they spawn
	if _planet_instance.has_signal("planet_loaded"):
		if not _planet_instance.is_connected("planet_loaded", _on_planet_loaded):
			_planet_instance.connect("planet_loaded", _on_planet_loaded)
	
	if debug_mode:
		print("Planet spawned at position: ", _planet_instance.global_position)
		print("Planet category: ", CATEGORY_NAMES.get(category, "Unknown"))
		if theme >= 0:
			print("Planet theme: ", THEME_NAMES.get(theme, "Unknown"))
	
	# Emit signal
	planet_spawned.emit(_planet_instance, Vector2i(grid_x, grid_y))
	planet_generation_completed.emit(_planet_instance)
	
	return _planet_instance

## Generate a parameter set for a random planet
func generate_random_planet_params() -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = _seed_value
	
	var params = {}
	
	# 30% chance for gas giant, 70% for terran
	params["planet_category"] = PlanetCategories.GASEOUS if rng.randf() < 0.3 else PlanetCategories.TERRAN
	
	if params["planet_category"] == PlanetCategories.TERRAN:
		# Random terran theme
		params["planet_theme"] = rng.randi() % PlanetThemes.GAS_GIANT
	else:
		# Gas giant theme
		params["planet_theme"] = PlanetThemes.GAS_GIANT
	
	# Random scale based on category
	if params["planet_category"] == PlanetCategories.GASEOUS:
		params["planet_scale"] = rng.randf_range(0.9, 1.1)
	else:
		params["planet_scale"] = rng.randf_range(0.8, 1.2)
	
	# Moon parameters
	if params["planet_category"] == PlanetCategories.GASEOUS:
		# Gas giants always have many moons
		params["moon_chance"] = 100
		params["min_moons"] = 3
		params["max_moons"] = 6
	else:
		params["moon_chance"] = rng.randi_range(30, 70)
		params["min_moons"] = 0
		params["max_moons"] = 3
	
	return params

## Manually set grid position and update
func set_grid_position(x: int, y: int) -> void:
	grid_x = x
	grid_y = y
	_update_seed_value()

## Clean up existing planet and moons
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

## Force a specific planet type
func force_planet_type(is_gaseous: bool, theme_index: int = -1) -> void:
	default_planet_category = PlanetCategories.GASEOUS if is_gaseous else PlanetCategories.TERRAN
	
	if not is_gaseous and theme_index >= 0 and theme_index < PlanetThemes.GAS_GIANT:
		default_terran_theme = theme_index + 1  # +1 because 0 is Random in the export enum

## Public getter for the spawned planet instance
func get_planet_instance() -> Node2D:
	return _planet_instance

## Public getter for moon instances
func get_moon_instances() -> Array:
	return _moon_instances

## Check if current planet is gaseous
func is_gaseous_planet() -> bool:
	return default_planet_category == PlanetCategories.GASEOUS

## Check if current planet is terran
func is_terran_planet() -> bool:
	return default_planet_category == PlanetCategories.TERRAN

## Get the category name for the current planet
func get_category_name() -> String:
	return "Gaseous" if is_gaseous_planet() else "Terran"

## Manually set a specific seed value
func set_seed_value(value: int) -> void:
	_seed_value = value
	_rng.seed = _seed_value

## Get the current seed value
func get_seed_value() -> int:
	return _seed_value

## Get a list of all available planet themes as strings
func get_available_themes(category_name: String = "") -> Array:
	var themes = []
	
	if category_name.to_lower() == "gaseous":
		themes.append("gas_giant")
	elif category_name.to_lower() == "terran":
		themes.append("arid")
		themes.append("ice")
		themes.append("lava")
		themes.append("lush")
		themes.append("desert")
		themes.append("alpine")
		themes.append("ocean")
	else:
		# Return all
		themes.append_array(get_available_themes("terran"))
		themes.append_array(get_available_themes("gaseous"))
	
	return themes

## Get a specific parameter for the planet from SeedManager
func get_deterministic_param(param_name: String, min_val: float, max_val: float, sub_id: int = 0) -> float:
	if has_node("/root/SeedManager"):
		# Generate a unique object ID based on our parameters
		var object_id = _seed_value + hash(param_name)
		return SeedManager.get_random_value(object_id, min_val, max_val, sub_id)
	else:
		# Fallback using local RNG
		return min_val + (max_val - min_val) * _rng.randf()

# PRIVATE METHODS

func _update_seed_value() -> void:
	if force_random_seed:
		# Generate completely random seed regardless of position
		_seed_value = randi()
		_rng.seed = _seed_value
	elif has_node("/root/SeedManager"):
		# Get base seed from SeedManager
		var base_seed = SeedManager.get_seed()
		
		# Add grid position to create unique seeds per grid cell
		if use_grid_position:
			_seed_value = base_seed + (grid_x * 1000) + (grid_y * 100) + local_seed_offset
		else:
			# Use position-based seed if not using grid
			var pos_hash = (int(global_position.x) * 13) + (int(global_position.y) * 7)
			_seed_value = base_seed + pos_hash + local_seed_offset
	else:
		# Fallback when SeedManager isn't available
		_seed_value = hash(str(grid_x) + str(grid_y) + str(local_seed_offset) + str(Time.get_unix_time_from_system()))
	
	# Initialize RNG with our seed
	_rng.seed = _seed_value

func _on_planet_loaded(planet) -> void:
	# Access moons that were created by the planet
	if planet and is_instance_valid(planet) and planet.moons.size() > 0:
		for moon in planet.moons:
			if is_instance_valid(moon):
				_moon_instances.append(moon)
				
				# Register each moon with EntityManager
				if has_node("/root/EntityManager"):
					EntityManager.register_entity(moon, "moon")
				
				if debug_mode:
					print("Moon registered: ", moon.moon_name)

func _on_seed_changed(_new_seed: int) -> void:
	# Just update seed, don't auto-respawn
	_update_seed_value()
	
	if debug_mode:
		print("PlanetSpawner updated with new seed: ", _seed_value)

func _clean_cache_if_needed() -> void:
	# Only clean cache occasionally
	var current_time = Time.get_ticks_msec()
	if current_time - _cache_last_cleaned < 10000:  # 10 seconds
		return
		
	_cache_last_cleaned = current_time
	
	# Check planet textures
	if texture_cache.planets.size() > MAX_CACHE_SIZE:
		var keys = texture_cache.planets.keys()
		keys.sort()  # Sort by seed value
		# Remove oldest half
		for i in range(keys.size() / 2):
			texture_cache.planets.erase(keys[i])
	
	# Check atmosphere textures
	if texture_cache.atmospheres.size() > MAX_CACHE_SIZE:
		var keys = texture_cache.atmospheres.keys()
		keys.sort()
		for i in range(keys.size() / 2):
			texture_cache.atmospheres.erase(keys[i])
	
	# Check moon textures
	if texture_cache.moons.size() > MAX_CACHE_SIZE:
		var keys = texture_cache.moons.keys()
		keys.sort()
		for i in range(keys.size() / 2):
			texture_cache.moons.erase(keys[i])
