# scripts/entities/planet_spawner.gd
# Updated planet spawner with proper terran/gaseous category support
extends Node2D
class_name PlanetSpawner

# Import planet classification constants
const PlanetThemes = preload("res://scripts/generators/planet_generator.gd").PlanetTheme
const PlanetCategories = preload("res://scripts/generators/planet_generator.gd").PlanetCategory

signal planet_spawned(planet_instance)
signal spawner_ready

# Planet configuration
@export_category("Planet Configuration")
@export var auto_spawn: bool = false
@export var planet_scene: PackedScene # Will be set to preload("res://scenes/world/planet.tscn") in _ready
@export var use_grid_position: bool = true
@export var grid_x: int = 0
@export var grid_y: int = 0
@export var local_seed_offset: int = 0  # Add to global seed for variation

# Planet properties
@export_category("Planet Properties")
@export var max_moons: int = 2
@export var moon_chance: int = 50 # Percentage chance to spawn moons
@export var planet_scale: float = 1.0
@export var custom_theme: int = -1  # -1 = random, otherwise use specific theme
@export var force_category: int = -1  # -1 = auto-determine, 0 = terran, 1 = gaseous
@export var moon_distance_factor_min: float = 1.8
@export var moon_distance_factor_max: float = 2.5
@export var max_orbit_deviation: float = 0.15
@export var moon_orbit_factor: float = 0.05

@export_category("Performance Options")
@export var use_texture_cache: bool = true
@export var pregenerate: bool = true

@export_category("Rendering")
@export var z_index_base: int = -10  # Base z-index for planets, adjust to render behind player

@export_category("Debug")
@export var debug_mode: bool = false

# Internal variables
var _seed_value: int = 0
var _planet_instance = null
var _moon_instances = []
var _initialized: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _planet_category: int = PlanetCategories.TERRAN  # Default to terran

# Texture cache shared between all planet spawners
static var texture_cache = {
	"planets": {},
	"atmospheres": {},
	"moons": {}
}

# Cache size control
const MAX_CACHE_SIZE = 30
var _cache_last_cleaned = 0

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
		print("Planet category: ", "Gaseous" if _planet_category == PlanetCategories.GASEOUS else "Terran")

func _update_seed_value() -> void:
	if has_node("/root/SeedManager"):
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
	
	# Determine planet category
	_determine_planet_category()

func _determine_planet_category() -> void:
	# If category is forced, use that
	if force_category >= 0:
		_planet_category = force_category
		return
	
	# If theme is specified and it's a gas giant, it's gaseous
	if custom_theme == PlanetThemes.GAS_GIANT:
		_planet_category = PlanetCategories.GASEOUS
		return
	
	# Otherwise determine based on seed
	var generator = PlanetGenerator.new()
	var theme = generator.get_planet_theme(_seed_value)
	_planet_category = PlanetGenerator.get_planet_category(theme)
	
	# Apply planet scale appropriately for gaseous planets in debug mode
	if _planet_category == PlanetCategories.GASEOUS and debug_mode:
		print("PlanetSpawner: Gaseous planet detected, using gas giant settings")

func _pregenerate_textures() -> void:
	# Start with the primary seed
	var theme: int
	
	if custom_theme >= 0:
		theme = custom_theme
	else:
		var generator = PlanetGenerator.new()
		
		# If we have a forced category, get a theme for that category
		if force_category >= 0:
			theme = generator.get_themed_planet_for_category(_seed_value, force_category) 
		else:
			# Otherwise get a random theme
			theme = generator.get_planet_theme(_seed_value)
	
	# Make sure base textures for this seed are cached
	if not texture_cache.planets.has(_seed_value):
		_generate_and_cache_planet_texture(_seed_value)
	
	if not texture_cache.atmospheres.has(_seed_value):
		_generate_and_cache_atmosphere_texture(_seed_value, theme)
	
	# Generate a few moon textures in advance
	for i in range(max_moons):
		var moon_seed = _seed_value + i * 100
		for moon_type in range(3):  # Generate for all moon types
			var cache_key = moon_seed * 10 + moon_type
			if not texture_cache.moons.has(cache_key):
				_generate_and_cache_moon_texture(moon_seed, moon_type)
	
	# Clean cache if it's getting too large
	_clean_cache_if_needed()

func _generate_and_cache_planet_texture(seed_value: int) -> Texture2D:
	var generator = PlanetGenerator.new()
	var texture = generator.create_planet_texture(seed_value)[0]
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

# Main planet spawning function - uses the determined category
func spawn_planet() -> Node2D:
	# Clean up any previously spawned planets
	cleanup()
	
	match _planet_category:
		PlanetCategories.TERRAN:
			return _spawn_planet_with_category(PlanetCategories.TERRAN)
		PlanetCategories.GASEOUS:
			return _spawn_planet_with_category(PlanetCategories.GASEOUS)
		_:
			# Fallback to terran if category is invalid
			return _spawn_planet_with_category(PlanetCategories.TERRAN)

# Specific function to spawn a terran planet
func spawn_terran_planet() -> Node2D:
	return _spawn_planet_with_category(PlanetCategories.TERRAN)

# Specific function to spawn a gaseous planet
func spawn_gaseous_planet() -> Node2D:
	return _spawn_planet_with_category(PlanetCategories.GASEOUS)

# Internal function to spawn a planet of a specific category
func _spawn_planet_with_category(category: int) -> Node2D:
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
	
	# Apply appropriate scale based on planet category
	var final_scale = planet_scale
	# For gaseous planets, we'll use a different scale factor
	# No need to reduce by 0.6 anymore since we're handling sizes by category
	_planet_instance.scale = Vector2(final_scale, final_scale)
	
	# Determine theme based on category if not specified
	var theme_to_use = custom_theme
	
	if theme_to_use < 0:
		# No specific theme - get one for the requested category
		var generator = PlanetGenerator.new()
		theme_to_use = generator.get_themed_planet_for_category(_seed_value, category)
	else:
		# If custom theme doesn't match category, override it
		var theme_category = PlanetGenerator.get_planet_category(theme_to_use)
		if theme_category != category:
			var generator = PlanetGenerator.new()
			theme_to_use = generator.get_themed_planet_for_category(_seed_value, category)
	
	# Set up the planet parameters
	var planet_params = {
		"seed_value": _seed_value,
		"grid_x": grid_x,
		"grid_y": grid_y,
		"max_moons": max_moons,
		"moon_chance": moon_chance,
		"min_moon_distance_factor": moon_distance_factor_min,
		"max_moon_distance_factor": moon_distance_factor_max,
		"max_orbit_deviation": max_orbit_deviation,
		"moon_orbit_factor": moon_orbit_factor,
		"use_texture_cache": use_texture_cache,
		"theme_override": theme_to_use,
		"category_override": category
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
		print("Planet spawned at position: ", _planet_instance.global_position)
		print("Planet category: ", "Gaseous" if category == PlanetCategories.GASEOUS else "Terran")
		if category == PlanetCategories.GASEOUS:
			print("Spawned a gaseous planet (Gas Giant)")
	
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
					print("Moon registered: ", moon.name)

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

func _on_seed_changed(_new_seed: int) -> void:
	# Update seed and respawn if already spawned
	_update_seed_value()
	
	if auto_spawn and _initialized:
		spawn_planet()
		
	if debug_mode:
		print("PlanetSpawner updated with new seed: ", _seed_value)
		print("New planet category: ", "Gaseous" if _planet_category == PlanetCategories.GASEOUS else "Terran")

# Force respawn with new parameters
func respawn(params: Dictionary = {}) -> Node2D:
	# Update parameters if provided
	if params.has("max_moons"):
		max_moons = params.max_moons
	if params.has("moon_chance"):
		moon_chance = params.moon_chance
	if params.has("planet_scale"):
		planet_scale = params.planet_scale
	if params.has("custom_theme"):
		custom_theme = params.custom_theme
	if params.has("force_category"):
		force_category = params.force_category
		_determine_planet_category()
	if params.has("grid_x"):
		grid_x = params.grid_x
	if params.has("grid_y"):
		grid_y = params.grid_y
	if params.has("local_seed_offset"):
		local_seed_offset = params.local_seed_offset
		_update_seed_value()
	if params.has("z_index_base"):
		z_index_base = params.z_index_base
	
	# Spawn new planet with updated parameters
	return spawn_planet()

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

# Public getter for the spawned planet instance
func get_planet_instance() -> Node2D:
	return _planet_instance

# Public getter for moon instances
func get_moon_instances() -> Array:
	return _moon_instances

# Check if current planet is gaseous
func is_gaseous_planet() -> bool:
	return _planet_category == PlanetCategories.GASEOUS

# Check if current planet is terran
func is_terran_planet() -> bool:
	return _planet_category == PlanetCategories.TERRAN

# Get a specific parameter for the planet from SeedManager
func get_deterministic_param(param_name: String, min_val: float, max_val: float, sub_id: int = 0) -> float:
	if has_node("/root/SeedManager"):
		# Generate a unique object ID based on our parameters
		var object_id = _seed_value + hash(param_name)
		return SeedManager.get_random_value(object_id, min_val, max_val, sub_id)
	else:
		# Fallback using local RNG
		return min_val + (max_val - min_val) * _rng.randf()
