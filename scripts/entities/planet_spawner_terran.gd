# scripts/entities/planet_spawner_terran.gd
# Specialized spawner for terran planets
extends PlanetSpawnerBase
class_name PlanetSpawnerTerran

# Terran Planet Theme - using PlanetThemes from parent class
@export_enum("Random", "Arid", "Ice", "Lava", "Lush", "Desert", "Alpine", "Ocean") 
var terran_theme: int = 0  # 0=Random, 1-7=Specific Terran theme

# Debug Options - Added to expose orbit debug settings
@export_category("Debug Options")
@export var debug_draw_orbits: bool = false
@export var debug_orbit_line_width: float = 1.0

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
	
	# Determine terran theme (don't generate it here, let planet.gd decide if it's random)
	var theme_to_use: int = -1
	
	if terran_theme > 0:
		# User selected specific theme (subtract 1 because 0 is Random in the export enum)
		theme_to_use = terran_theme - 1
		
		# Verify it's a valid terran theme
		if theme_to_use >= PlanetThemes.JUPITER:
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
		"moon_chance": 40,  # Fixed moon chance for terran planets
		"min_moon_distance_factor": 2.2,  # INCREASED: from 1.8 to 2.2 for longer orbit
		"max_moon_distance_factor": 3.0,  # INCREASED: from 2.5 to 3.0 for longer orbit
		"max_orbit_deviation": 0.15,
		"moon_orbit_factor": 0.05,
		"use_texture_cache": use_texture_cache,
		"theme_override": theme_to_use,
		"category_override": PlanetCategories.TERRAN,  # Force terran category
		"moon_orbit_speed_factor": moon_orbit_speed_factor,  # Pass the moon orbit speed factor
		"is_random_theme": terran_theme == 0,  # Flag indicating if we want a random theme
		
		# IMPORTANT: Pass debug options to see orbits
		"debug_draw_orbits": debug_draw_orbits,
		"debug_orbit_line_width": debug_orbit_line_width,
		
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
		var planet_size = PlanetGeneratorBase.get_planet_size(_seed_value, false)  # false = terran
		print("PlanetSpawnerTerran: Spawned terran planet at position ", _planet_instance.global_position)
		print("PlanetSpawnerTerran: Selected terran_theme=", terran_theme, " (0=Random, 1-7=specific)")
		print("PlanetSpawnerTerran: Planet size: ", planet_size, " pixels")
		if _planet_instance.has_method("get_theme_name"):
			print("PlanetSpawnerTerran: Actual theme used: ", _planet_instance.get_theme_name())
	
	# Check if texture cache needs cleaning
	_check_and_clean_cache()
	
	return _planet_instance

# Force a specific terran theme - Used for direct API calls
func force_terran_theme(theme_index: int) -> void:
	if theme_index >= 0 and theme_index < PlanetThemes.JUPITER:
		terran_theme = theme_index + 1  # +1 because 0 is Random in the export enum
		
	# Update and respawn if already initialized
	if _initialized:
		_update_seed_value()
		spawn_planet()

# Toggle debug orbit visualization
func toggle_orbit_debug(enabled: bool = true) -> void:
	debug_draw_orbits = enabled
	
	# Update the existing planet if it's already spawned
	if _planet_instance and is_instance_valid(_planet_instance) and _planet_instance.has_method("toggle_orbit_debug"):
		_planet_instance.toggle_orbit_debug(enabled)

# Set orbit line width
func set_orbit_line_width(width: float) -> void:
	debug_orbit_line_width = width
	
	# Update the existing planet if it's already spawned
	if _planet_instance and is_instance_valid(_planet_instance) and _planet_instance.has_method("set_orbit_line_width"):
		_planet_instance.set_orbit_line_width(width)

# Override base class method for API compatibility
func force_planet_type(is_gaseous: bool, theme_index: int = -1) -> void:
	if is_gaseous:
		push_warning("PlanetSpawnerTerran: Cannot force gaseous planet type on a terran planet spawner")
		return
		
	force_terran_theme(theme_index)
