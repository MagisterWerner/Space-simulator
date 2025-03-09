# scripts/entities/planet_spawner_gaseous.gd
# Specialized spawner for gaseous planets
class_name PlanetSpawnerGaseous
extends PlanetSpawnerBase

# Gas giant type constants
enum GasGiantType {
	JUPITER = 0,  # Jupiter-like (beige/tan tones)
	SATURN = 1,   # Saturn-like (golden tones)
	URANUS = 2,   # Uranus-like (cyan/teal tones)
	NEPTUNE = 3   # Neptune-like (blue tones)
}

# Gaseous Planet Type
@export_enum("Random", "Jupiter-like", "Saturn-like", "Uranus-like", "Neptune-like") 
var gaseous_theme: int = 0  # 0=Random, 1-4=Specific Gaseous theme

func _init() -> void:
	# Override the base class properties with gaseous-specific defaults
	moon_chance = 100  # Gas giants always have moons
	planet_scale = 1.25  # Larger scale for gas giants

# Override the spawner type method for debugging
func get_spawner_type() -> String:
	return "PlanetSpawnerGaseous"

# Override the spawn_planet method to specifically spawn gaseous planets
func spawn_planet() -> Node2D:
	# Clean up any previously spawned planets
	cleanup()
	
	# Spawn a gaseous planet
	return _spawn_gaseous_planet()

# Implementation of is_terran_planet for API compatibility
func is_terran_planet() -> bool:
	return false

# Implementation of is_gaseous_planet for API compatibility
func is_gaseous_planet() -> bool:
	return true

# Spawn a gaseous planet with fixed parameters
func _spawn_gaseous_planet() -> Node2D:
	# Load the gaseous planet scene
	var gaseous_scene = load("res://scenes/world/planet_gaseous.tscn")
	if not gaseous_scene:
		push_error("PlanetSpawnerGaseous: Planet gaseous scene is not loaded!")
		return null
		
	# Create planet instance
	_planet_instance = gaseous_scene.instantiate()
	add_child(_planet_instance)
	
	# Set z-index for rendering order
	_planet_instance.z_index = z_index_base
	
	# Calculate position
	var spawn_position = _calculate_spawn_position()
	_planet_instance.global_position = spawn_position
	
	# Apply scale
	_planet_instance.scale = Vector2(planet_scale, planet_scale)
	
	# Determine gas giant type
	var gas_giant_type: int = -1  # -1 means let planet.gd decide
	
	if gaseous_theme > 0:
		# User selected specific gas giant type (1=Jupiter, 2=Saturn, etc.)
		gas_giant_type = gaseous_theme - 1
	
	# Force-generate a random gas giant seed if needed
	var random_gas_seed: int = _seed_value
	if gaseous_theme == 0:
		# Generate a unique seed for gas giant type selection
		random_gas_seed = _seed_value * 23 + 41  # Different prime multiplier
	
	# Set up the planet parameters
	var planet_params = {
		"seed_value": _seed_value,
		"random_gas_seed": random_gas_seed,
		"grid_x": grid_x,
		"grid_y": grid_y,
		"moon_chance": moon_chance,
		"min_moon_distance_factor": 1.8,
		"max_moon_distance_factor": 2.5,
		"max_orbit_deviation": 0.15,
		"moon_orbit_factor": 0.05,
		"use_texture_cache": use_texture_cache,
		"theme_override": PlanetGeneratorBase.PlanetTheme.GAS_GIANT,  # Force gas giant theme
		"category_override": PlanetGeneratorBase.PlanetCategory.GASEOUS,  # Force gaseous category
		"moon_orbit_speed_factor": moon_orbit_speed_factor,  # Pass the moon orbit speed factor
		"gas_giant_type_override": gas_giant_type,  # Pass our gas giant type override
		"is_random_gaseous": gaseous_theme == 0,  # Flag indicating if we want a random gas giant
		"debug_planet_generation": debug_planet_generation
	}
	
	# If debug is enabled, add additional debug info to the parameters
	if debug_planet_generation:
		planet_params["debug_gas_theme_source"] = "From gaseous_theme export: " + str(gaseous_theme)
	
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
		print("PlanetSpawnerGaseous: Spawned gaseous planet at position ", _planet_instance.global_position)
		print("PlanetSpawnerGaseous: Selected gaseous_theme=", gaseous_theme, " (0=Random, 1-4=specific)")
		if _planet_instance.has_method("get_gas_giant_type_name"):
			print("PlanetSpawnerGaseous: Actual gas giant type: ", _planet_instance.get_gas_giant_type_name())
	
	# Check if texture cache needs cleaning
	_check_and_clean_cache()
	
	return _planet_instance

# Force a specific gas giant type - Used for direct API calls
func force_gas_giant_type(type_index: int) -> void:
	if type_index >= 0 and type_index < 4:
		gaseous_theme = type_index + 1  # +1 because 0 is Random
		
	# Update and respawn if already initialized
	if _initialized:
		_update_seed_value()
		spawn_planet()

# Override base class method for API compatibility
func force_planet_type(is_gaseous: bool, theme_index: int = -1) -> void:
	if !is_gaseous:
		push_warning("PlanetSpawnerGaseous: Cannot force terran planet type on a gaseous planet spawner")
		return
		
	force_gas_giant_type(theme_index)

# Get gas giant type name for debugging
func get_gas_giant_type_name() -> String:
	if gaseous_theme == 0:
		return "Random"
	elif gaseous_theme - 1 == GasGiantType.JUPITER:
		return "Jupiter-like"
	elif gaseous_theme - 1 == GasGiantType.SATURN:
		return "Saturn-like"
	elif gaseous_theme - 1 == GasGiantType.URANUS:
		return "Uranus-like"
	elif gaseous_theme - 1 == GasGiantType.NEPTUNE:
		return "Neptune-like"
	else:
		return "Unknown"
