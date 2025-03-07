# scripts/entities/planet_spawner.gd
# ==========================
# PURPOSE:
#   An optimized planet spawner that enables procedurally generating planets
#   with precise control over their type, appearance, and characteristics.
#
# USAGE:
#   1. Basic planet spawning:
#      var planet = $PlanetSpawner.spawn_planet()  # Random planet
#
#   2. Spawn specific planet type by category and theme:
#      var lush_planet = $PlanetSpawner.spawn_specific_planet("terran", "lush")
#      var gas_giant = $PlanetSpawner.spawn_specific_planet("gaseous")
#
#   3. Convenient helper methods:
#      var ice_planet = $PlanetSpawner.spawn_terran_planet("ice")
#      var gas_giant = $PlanetSpawner.spawn_gaseous_planet()
#
#   4. Spawn planet at specific grid position:
#      $PlanetSpawner.set_grid_position(3, 5)
#      var planet = $PlanetSpawner.spawn_terran_planet("ocean")
#
#   5. Advanced customization:
#      var params = {
#         "category": "terran",
#         "theme": "alpine",
#         "grid_x": 7,
#         "grid_y": 2,
#         "planet_scale": 1.2,
#         "moon_chance": 75
#      }
#      var custom_planet = $PlanetSpawner.spawn_with_params(params)
#
# AVAILABLE PLANET TYPES:
#   - Terran (rocky planets): "arid", "ice", "lava", "lush", "desert", "alpine", "ocean"
#   - Gaseous (gas giants): currently only one type, specify simply as "gaseous"
#
# NOTES:
#   - Planets are procedurally generated based on a seed value
#   - The same seed will always produce the same planet
#   - All planets can have moons based on type/parameters

extends Node2D
class_name PlanetSpawner

# Import planet classification constants
const PlanetThemes = preload("res://scripts/generators/planet_generator.gd").PlanetTheme
const PlanetCategories = preload("res://scripts/generators/planet_generator.gd").PlanetCategory

signal planet_spawned(planet_instance)
signal spawner_ready

# Planet Type Selection - SIMPLIFIED to prevent mixing
@export_category("Planet Type")
@export_enum("Terran", "Gaseous") var planet_category: int = 0  # 0=Terran, 1=Gaseous

# Terran Planet Theme (only used when planet_category is Terran)
@export_enum("Random", "Arid", "Ice", "Lava", "Lush", "Desert", "Alpine", "Ocean") 
var terran_theme: int = 0  # 0=Random, 1-7=Specific Terran theme

# Random Seed Option 
@export var force_random_seed: bool = false  # When true, ignores grid positioning

# Planet Configuration
@export_category("Planet Configuration")
@export var auto_spawn: bool = false
@export var planet_scene: PackedScene # Will be set to preload("res://scenes/world/planet.tscn") in _ready
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
	# Load planet scene if not set
	if planet_scene == null:
		planet_scene = load("res://scenes/world/planet.tscn")
	
	# Connect to SeedManager signal if available
	if has_node("/root/SeedManager") and SeedManager.has_signal("seed_changed"):
		SeedManager.seed_changed.connect(_on_seed_changed)
	
	# Initialize after a frame to ensure autoloads are ready
	call_deferred("_initialize")

func _initialize() -> void:
	if _initialized:
		return
	
	# Initialize seed value
	_update_seed_value()
	
	# Pregenerate textures if enabled
	if pregenerate and use_texture_cache:
		_pregenerate_textures()
	
	# Automatically spawn if set
	if auto_spawn:
		spawn_planet()
	
	_initialized = true
	spawner_ready.emit()
	
	if debug_mode:
		print("PlanetSpawner initialized with seed: ", _seed_value)
		print("Planet category: ", "Gaseous" if planet_category == PlanetCategories.GASEOUS else "Terran")

# Spawn a planet with specific category and theme (as strings)
func spawn_specific_planet(category_name: String = "random", theme_name: String = "random") -> Node2D:
	# Determine category enum value
	var category_enum: int
	if category_name == "random":
		category_enum = planet_category  # Use exported value
	else:
		category_name = category_name.to_lower()
		category_enum = CATEGORY_MAP.get(category_name, planet_category)
	
	# Determine theme enum value
	var theme_enum: int = -1  # -1 means random
	if theme_name != "random":
		theme_name = theme_name.to_lower()
		theme_enum = THEME_MAP.get(theme_name, -1)
	
	# Special case for gaseous planets (only gas_giant theme available)
	if category_enum == PlanetCategories.GASEOUS:
		theme_enum = PlanetThemes.GAS_GIANT
	
	# Update internal state
	planet_category = category_enum
	if category_enum == PlanetCategories.TERRAN and theme_enum >= 0:
		# +1 because 0 is "Random" in the export enum
		terran_theme = theme_enum + 1
	
	# Spawn the planet with updated parameters
	return spawn_planet()

# Convenient method to spawn a terran planet with specific theme
func spawn_terran_planet(theme_name: String = "random") -> Node2D:
	return spawn_specific_planet("terran", theme_name)

# Convenient method to spawn a gaseous planet
func spawn_gaseous_planet() -> Node2D:
	return spawn_specific_planet("gaseous")

# Spawn a planet with a complete parameter dictionary
func spawn_with_params(params: Dictionary) -> Node2D:
	# Extract and apply parameters
	if params.has("category"):
		var category_name = params.category.to_lower()
		if CATEGORY_MAP.has(category_name):
			planet_category = CATEGORY_MAP[category_name]
	
	if params.has("theme") and planet_category == PlanetCategories.TERRAN:
		var theme_name = params.theme.to_lower()
		if THEME_MAP.has(theme_name):
			terran_theme = THEME_MAP[theme_name] + 1  # +1 for export enum offset
	
	# Apply additional parameters
	if params.has("moon_chance"):
		moon_chance = params.moon_chance
	
	if params.has("planet_scale"):
		planet_scale = params.planet_scale
	
	if params.has("grid_x"):
		grid_x = params.grid_x
	
	if params.has("grid_y"):
		grid_y = params.grid_y
	
	if params.has("local_seed_offset"):
		local_seed_offset = params.local_seed_offset
	
	if params.has("z_index_base"):
		z_index_base = params.z_index_base
	
	if params.has("moon_orbit_speed_factor"):
		moon_orbit_speed_factor = params.moon_orbit_speed_factor
	
	# Update seed and spawn
	_update_seed_value()
	return spawn_planet()

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
	# Create planet instance
	_planet_instance = planet_scene.instantiate()
	add_child(_planet_instance)
	
	# Set z-index for rendering order
	_planet_instance.z_index = z_index_base
	
	# Calculate position
	var spawn_position = Vector2.ZERO
	if use_grid_position and has_node("/root/GridManager"):
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
			if debug_mode:
				push_warning("Invalid terran theme selected; reverting to random terran theme")
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
		if not _planet_instance.is_connected("planet_loaded", Callable(self, "_on_planet_loaded")):
			_planet_instance.connect("planet_loaded", Callable(self, "_on_planet_loaded"))
	
	if debug_mode:
		print("Terran planet spawned at position: ", _planet_instance.global_position)
		if theme_to_use >= 0 and theme_to_use < PlanetThemes.size():
			var theme_names = ["Arid", "Ice", "Lava", "Lush", "Desert", "Alpine", "Ocean", "Gas Giant"]
			print("Planet theme: ", theme_names[theme_to_use])
	
	# Emit spawned signal
	planet_spawned.emit(_planet_instance)
	
	return _planet_instance

# Spawn a gaseous planet with fixed parameters
func _spawn_gaseous_planet() -> Node2D:
	# Create planet instance
	_planet_instance = planet_scene.instantiate()
	add_child(_planet_instance)
	
	# Set z-index for rendering order
	_planet_instance.z_index = z_index_base
	
	# Calculate position
	var spawn_position = Vector2.ZERO
	if use_grid_position and has_node("/root/GridManager"):
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
		if not _planet_instance.is_connected("planet_loaded", Callable(self, "_on_planet_loaded")):
			_planet_instance.connect("planet_loaded", Callable(self, "_on_planet_loaded"))
	
	if debug_mode:
		print("Gaseous planet (Gas Giant) spawned at position: ", _planet_instance.global_position)
		print("Gas giant type: ", _seed_value % 4)  # Shows which of the 4 gas giant palettes is used
	
	# Emit spawned signal
	planet_spawned.emit(_planet_instance)
	
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
				
				if debug_mode:
					print("Moon registered: ", moon.moon_name)

# Clean up existing planet and moons
func cleanup() -> void:
	# Clean up existing planet and moons
	if _planet_instance and is_instance_valid(_planet_instance):
		# Disconnect signal to avoid issues
		if _planet_instance.has_signal("planet_loaded"):
			if _planet_instance.is_connected("planet_loaded", Callable(self, "_on_planet_loaded")):
				_planet_instance.disconnect("planet_loaded", Callable(self, "_on_planet_loaded"))
		
		# Deregister from EntityManager
		if has_node("/root/EntityManager"):
			EntityManager.deregister_entity(_planet_instance)
		
		_planet_instance.queue_free()
		_planet_instance = null
	
	# Clear moon references
	_moon_instances.clear()

func _on_seed_changed(new_seed: int) -> void:
	# Update seed and respawn if already spawned
	_update_seed_value()
	
	if auto_spawn and _initialized:
		spawn_planet()
		
	if debug_mode:
		print("PlanetSpawner updated with new seed: ", _seed_value)
		print("Planet category: ", "Gaseous" if planet_category == PlanetCategories.GASEOUS else "Terran")

# Set grid position and update
func set_grid_position(x: int, y: int) -> void:
	grid_x = x
	grid_y = y
	_update_seed_value()
	
	# Update position if using grid
	if use_grid_position and has_node("/root/GridManager") and _planet_instance and is_instance_valid(_planet_instance):
		var new_pos = GridManager.cell_to_world(Vector2i(grid_x, grid_y))
		_planet_instance.global_position = new_pos
	
	if debug_mode:
		print("PlanetSpawner grid position updated to: ", Vector2i(grid_x, grid_y))

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

# Get a specific parameter for the planet from SeedManager
func get_deterministic_param(param_name: String, min_val: float, max_val: float, sub_id: int = 0) -> float:
	if has_node("/root/SeedManager"):
		# Generate a unique object ID based on our parameters
		var object_id = _seed_value + hash(param_name)
		return SeedManager.get_random_value(object_id, min_val, max_val, sub_id)
	else:
		# Fallback using local RNG
		return min_val + (max_val - min_val) * _rng.randf()
