# scripts/entities/planet_spawner.gd
# Enhanced and simplified planet spawner that uses GameSettings for consistent generation
extends Node2D
class_name PlanetSpawner

# Import planet classification constants
const PlanetThemes = preload("res://scripts/generators/planet_generator.gd").PlanetTheme
const PlanetCategories = preload("res://scripts/generators/planet_generator.gd").PlanetCategory

signal planet_spawned(planet_instance)
signal spawner_ready

# Planet Type Selection - SIMPLIFIED to prevent mixing
@export_enum("Terran", "Gaseous") var planet_category: int = 0  # 0=Terran, 1=Gaseous

# Terran Planet Theme (only used when planet_category is Terran)
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
@export var moon_chance: int = 50  # Percentage chance for terran planets to spawn moons
@export var planet_scale: float = 1.0
@export var moon_orbit_speed_factor: float = 1.0  # Multiplier for moon orbit speed

@export_category("Performance Options")
@export var use_texture_cache: bool = true
@export var pregenerate: bool = true

@export_category("Rendering")
@export var z_index_base: int = -10  # Base z-index for planets

# Internal variables
var _seed_value: int = 0
var _planet_instance = null
var _moon_instances = []
var _initialized: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var game_settings: GameSettings = null

# Hardcoded planet scene reference
var planet_scene: PackedScene = preload("res://scenes/world/planet.tscn")

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
	
	# Pregenerate textures if enabled
	if pregenerate and use_texture_cache:
		_pregenerate_textures()
	
	# Always spawn planet immediately - removed auto_spawn check
	spawn_planet()
	
	_initialized = true
	spawner_ready.emit()
	
	# Debug output
	if game_settings and game_settings.debug_mode:
		print("PlanetSpawner: Initialized at grid position (%d, %d) with seed: %d" % 
			  [grid_x, grid_y, _seed_value])

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

func _pregenerate_textures() -> void:
	# Get theme for this planet
	var theme: int = -1
	
	if planet_category == PlanetCategories.GASEOUS:
		# For gaseous, only GAS_GIANT is available
		theme = PlanetThemes.GAS_GIANT
	else:
		# For Terran, either specific theme or random
		if terran_theme > 0:
			theme = terran_theme - 1  # Convert from enum dropdown (1-7) to actual theme (0-6)
		else:
			# Random terran theme
			var generator = PlanetGenerator.new()
			theme = generator.get_themed_planet_for_category(_seed_value, PlanetCategories.TERRAN)
	
	# Make sure base textures for this seed are cached
	if not texture_cache.planets.has(_seed_value):
		_generate_and_cache_planet_texture(_seed_value, theme)
	
	if not texture_cache.atmospheres.has(_seed_value):
		_generate_and_cache_atmosphere_texture(_seed_value, theme)
	
	# Generate just one moon texture type for performance (we'll generate others on demand)
	var moon_seed = _seed_value + 100
	var cache_key = moon_seed * 10 + 0  # 0 = ROCKY type
	if not texture_cache.moons.has(cache_key):
		_generate_and_cache_moon_texture(moon_seed, 0)
	
	# Clean cache if it's getting too large
	_clean_cache_if_needed()

func _generate_and_cache_planet_texture(seed_value: int, theme: int = -1) -> Texture2D:
	var generator = PlanetGenerator.new()
	var texture = generator.create_planet_texture(seed_value, theme)[0]
	texture_cache.planets[seed_value] = texture
	return texture

func _generate_and_cache_atmosphere_texture(seed_value: int, theme: int) -> Texture2D:
	var atmosphere_generator = AtmosphereGenerator.new()
	var atm_data = atmosphere_generator.generate_atmosphere_data(theme, seed_value)
	var texture = atmosphere_generator.generate_atmosphere_texture(
		theme, seed_value, atm_data.color, atm_data.thickness)
	texture_cache.atmospheres[seed_value] = texture
	return texture

func _generate_and_cache_moon_texture(seed_value: int, moon_type: int = 0) -> Texture2D:
	var moon_generator = MoonGenerator.new()
	var cache_key = seed_value * 10 + moon_type  # Combine seed and type for unique key
	var texture = moon_generator.create_moon_texture(seed_value, moon_type)
	texture_cache.moons[cache_key] = texture
	return texture

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

# Main spawn function - dispatches to correct type
func spawn_planet() -> Node2D:
	# Clean up any previously spawned planets
	cleanup()
	
	# Directly dispatch based on chosen category
	if planet_category == PlanetCategories.GASEOUS:
		return _spawn_gaseous_planet()
	else:
		return _spawn_terran_planet()

# Spawn a terran planet with fixed parameters
func _spawn_terran_planet() -> Node2D:
	# Check if the planet scene is valid
	if planet_scene == null:
		push_error("PlanetSpawner: Planet scene is not loaded!")
		return null
	
	# Create planet instance
	_planet_instance = planet_scene.instantiate()
	add_child(_planet_instance)
	
	# Set z-index for rendering order
	_planet_instance.z_index = z_index_base
	
	# Calculate position
	var spawn_position = Vector2.ZERO
	if use_grid_position:
		# Use GameSettings or GridManager to get the cell position
		if game_settings:
			spawn_position = game_settings.get_cell_world_position(Vector2i(grid_x, grid_y))
		elif has_node("/root/GridManager"):
			spawn_position = GridManager.cell_to_world(Vector2i(grid_x, grid_y))
		
		_planet_instance.global_position = spawn_position
	else:
		_planet_instance.global_position = global_position
	
	# Apply scale
	_planet_instance.scale = Vector2(planet_scale, planet_scale)
	
	# Determine terran theme
	var theme_to_use = -1  # Default to random
	
	if terran_theme > 0:
		# User selected specific theme (subtract 1 because 0 is Random in the export enum)
		theme_to_use = terran_theme - 1
		
		# Verify it's really a terran theme (safety check)
		if theme_to_use >= PlanetThemes.GAS_GIANT:
			if game_settings and game_settings.debug_mode:
				print("Invalid terran theme selected; reverting to random terran theme")
			theme_to_use = -1
	
	if theme_to_use < 0:
		# Pick a random terran theme
		var generator = PlanetGenerator.new()
		theme_to_use = generator.get_themed_planet_for_category(_seed_value, PlanetCategories.TERRAN)
	
	# Set up the planet parameters
	var planet_params = {
		"seed_value": _seed_value,
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
		"moon_orbit_speed_factor": moon_orbit_speed_factor  # Pass the moon orbit speed factor
	}
	
	# Initialize the planet with our parameters
	_planet_instance.initialize(planet_params)
	
	# Register the planet with EntityManager if available
	if has_node("/root/EntityManager"):
		EntityManager.register_entity(_planet_instance, "planet")
	
	# Connect to planet's loaded signal to handle moons if they spawn
	if _planet_instance.has_signal("planet_loaded"):
		if not _planet_instance.is_connected("planet_loaded", _on_planet_loaded):
			_planet_instance.connect("planet_loaded", _on_planet_loaded)
	
	# Emit spawned signal
	planet_spawned.emit(_planet_instance)
	
	# Debug output
	if game_settings and game_settings.debug_mode:
		print("Spawned terran planet at position ", _planet_instance.global_position)
		print("Planet theme: ", _get_theme_name(theme_to_use))
	
	return _planet_instance

# Spawn a gaseous planet with fixed parameters
func _spawn_gaseous_planet() -> Node2D:
	# Check if the planet scene is valid
	if planet_scene == null:
		push_error("PlanetSpawner: Planet scene is not loaded!")
		return null
		
	# Create planet instance
	_planet_instance = planet_scene.instantiate()
	add_child(_planet_instance)
	
	# Set z-index for rendering order
	_planet_instance.z_index = z_index_base
	
	# Calculate position
	var spawn_position = Vector2.ZERO
	if use_grid_position:
		# Use GameSettings or GridManager to get the cell position
		if game_settings:
			spawn_position = game_settings.get_cell_world_position(Vector2i(grid_x, grid_y))
		elif has_node("/root/GridManager"):
			spawn_position = GridManager.cell_to_world(Vector2i(grid_x, grid_y))
		
		_planet_instance.global_position = spawn_position
	else:
		_planet_instance.global_position = global_position
	
	# Apply scale
	_planet_instance.scale = Vector2(planet_scale, planet_scale)
	
	# Set up the planet parameters - always gas giant for gaseous category
	var planet_params = {
		"seed_value": _seed_value,
		"grid_x": grid_x,
		"grid_y": grid_y,
		"moon_chance": 100,  # Always spawn moons for gas giants
		"min_moon_distance_factor": 1.8,
		"max_moon_distance_factor": 2.5,
		"max_orbit_deviation": 0.15,
		"moon_orbit_factor": 0.05,
		"use_texture_cache": use_texture_cache,
		"theme_override": PlanetThemes.GAS_GIANT,  # Force gas giant theme
		"category_override": PlanetCategories.GASEOUS,  # Force gaseous category
		"moon_orbit_speed_factor": moon_orbit_speed_factor  # Pass the moon orbit speed factor
	}
	
	# Initialize the planet with our parameters
	_planet_instance.initialize(planet_params)
	
	# Register the planet with EntityManager if available
	if has_node("/root/EntityManager"):
		EntityManager.register_entity(_planet_instance, "planet")
	
	# Connect to planet's loaded signal to handle moons if they spawn
	if _planet_instance.has_signal("planet_loaded"):
		if not _planet_instance.is_connected("planet_loaded", _on_planet_loaded):
			_planet_instance.connect("planet_loaded", _on_planet_loaded)
	
	# Emit spawned signal
	planet_spawned.emit(_planet_instance)
	
	# Debug output
	if game_settings and game_settings.debug_mode:
		print("Spawned gaseous planet (Gas Giant) at position ", _planet_instance.global_position)
		print("Gas giant type: ", _seed_value % 4)  # Shows which of the 4 gas giant palettes is used
	
	return _planet_instance

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
			print("PlanetSpawner: Updated position to grid (%d, %d)" % [grid_x, grid_y])

# Force a specific planet type
func force_planet_type(is_gaseous: bool, theme_index: int = -1) -> void:
	planet_category = PlanetCategories.GASEOUS if is_gaseous else PlanetCategories.TERRAN
	
	if not is_gaseous and theme_index >= 0 and theme_index < PlanetThemes.GAS_GIANT:
		terran_theme = theme_index + 1  # +1 because 0 is Random in the export enum
		
	# Update and respawn if already initialized
	if _initialized:
		_update_seed_value()
		spawn_planet()

# Public getter for the spawned planet instance
func get_planet_instance() -> Node2D:
	return _planet_instance

# Public getter for moon instances
func get_moon_instances() -> Array:
	return _moon_instances

# Check if current planet is gaseous
func is_gaseous_planet() -> bool:
	return planet_category == PlanetCategories.GASEOUS

# Check if current planet is terran
func is_terran_planet() -> bool:
	return planet_category == PlanetCategories.TERRAN

# Get the category name for the current planet
func get_category_name() -> String:
	return "Gaseous" if is_gaseous_planet() else "Terran"

# Get a specific parameter for the planet from seed
func get_deterministic_param(param_name: String, min_val: float, max_val: float, sub_id: int = 0) -> float:
	if game_settings:
		# Use GameSettings for deterministic values
		var object_id = _seed_value + hash(param_name)
		return game_settings.get_random_value(object_id, min_val, max_val, sub_id)
	elif has_node("/root/SeedManager"):
		# Fallback to SeedManager
		var object_id = _seed_value + hash(param_name)
		return SeedManager.get_random_value(object_id, min_val, max_val, sub_id)
	else:
		# Local fallback
		return min_val + (max_val - min_val) * _rng.randf()

# Get theme name for debugging
func _get_theme_name(theme_id: int) -> String:
	match theme_id:
		PlanetThemes.ARID: return "Arid"
		PlanetThemes.ICE: return "Ice"
		PlanetThemes.LAVA: return "Lava"
		PlanetThemes.LUSH: return "Lush"
		PlanetThemes.DESERT: return "Desert"
		PlanetThemes.ALPINE: return "Alpine"
		PlanetThemes.OCEAN: return "Ocean"
		PlanetThemes.GAS_GIANT: return "Gas Giant"
		_: return "Unknown"
