# scripts/entities/planet_spawner.gd
# A script for spawning procedural planets with atmosphere and moons
# based on the current game seed
extends Node2D
class_name PlanetSpawner

signal planet_spawned(planet_instance)
signal spawner_ready

# Planet configuration
@export_category("Planet Configuration")
@export var auto_spawn: bool = false
@export var planet_scene: PackedScene = preload("res://scenes/world/planet.tscn")
@export var moon_scene: PackedScene = preload("res://scenes/world/moon.tscn")
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
@export var moon_distance_factor_min: float = 1.8
@export var moon_distance_factor_max: float = 2.5
@export var max_orbit_deviation: float = 0.15

@export_category("Debug")
@export var debug_mode: bool = false

# Internal variables
var _seed_value: int = 0
var _planet_instance = null
var _moon_instances = []
var _initialized: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	# Connect to SeedManager signal
	if has_node("/root/SeedManager") and SeedManager.has_signal("seed_changed"):
		SeedManager.seed_changed.connect(_on_seed_changed)
	
	# Initialize after a frame to ensure autoloads are ready
	call_deferred("_initialize")

func _initialize() -> void:
	if _initialized:
		return
	
	# Initialize seed value
	_update_seed_value()
	
	# Automatically spawn if set
	if auto_spawn:
		spawn_planet()
	
	_initialized = true
	spawner_ready.emit()
	
	if debug_mode:
		print("PlanetSpawner initialized with seed: ", _seed_value)

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

func spawn_planet() -> Node2D:
	# Clean up any previously spawned planets
	cleanup()
	
	# Create planet instance
	_planet_instance = planet_scene.instantiate()
	add_child(_planet_instance)
	
	# Calculate position
	var spawn_position = Vector2.ZERO
	if use_grid_position and has_node("/root/GridManager"):
		spawn_position = GridManager.cell_to_world(Vector2i(grid_x, grid_y))
		_planet_instance.global_position = spawn_position
	else:
		_planet_instance.global_position = global_position
	
	# Scale the planet
	_planet_instance.scale = Vector2(planet_scale, planet_scale)
	
	# Set up the planet parameters
	var planet_params = {
		"seed_value": _seed_value,
		"grid_x": grid_x,
		"grid_y": grid_y,
		"max_moons": max_moons,
		"moon_chance": moon_chance,
		"min_moon_distance_factor": moon_distance_factor_min,
		"max_moon_distance_factor": moon_distance_factor_max,
		"max_orbit_deviation": max_orbit_deviation
	}
	
	# If a specific theme is requested, add it to the parameters
	if custom_theme >= 0:
		planet_params["theme_override"] = custom_theme
	
	# Initialize the planet with our parameters
	_planet_instance.initialize(planet_params)
	
	# Register the planet with EntityManager if available
	if has_node("/root/EntityManager"):
		EntityManager.register_entity(_planet_instance, "planet")
	
	# Connect to planet's loaded signal to handle moons if they spawn
	if _planet_instance.has_signal("planet_loaded"):
		_planet_instance.planet_loaded.connect(_on_planet_loaded)
	
	if debug_mode:
		print("Planet spawned at position: ", _planet_instance.global_position)
	
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
			if _planet_instance.planet_loaded.is_connected(_on_planet_loaded):
				_planet_instance.planet_loaded.disconnect(_on_planet_loaded)
		
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
	if params.has("grid_x"):
		grid_x = params.grid_x
	if params.has("grid_y"):
		grid_y = params.grid_y
	if params.has("local_seed_offset"):
		local_seed_offset = params.local_seed_offset
		_update_seed_value()
	
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

# Get a specific parameter for the planet from SeedManager
func get_deterministic_param(param_name: String, min_val: float, max_val: float, sub_id: int = 0) -> float:
	if has_node("/root/SeedManager"):
		# Generate a unique object ID based on our parameters
		var object_id = _seed_value + hash(param_name)
		return SeedManager.get_random_value(object_id, min_val, max_val, sub_id)
	else:
		# Fallback using local RNG
		return min_val + (max_val - min_val) * _rng.randf()
