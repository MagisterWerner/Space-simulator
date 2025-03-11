# scripts/world/world_generator.gd
# ========================
# Purpose:
#   Procedurally generates the game world based on GameSettings
#   Handles spawning of planets, asteroids, and stations
#   Maintains consistent generation based on the game seed

extends Node
class_name WorldGenerator

signal world_generation_started
signal world_generation_completed
signal entity_generated(entity, type, cell)

# References to required components
var game_settings: GameSettings = null
var seed_manager = null

# Scene references
var planet_spawner_terran_scene: PackedScene
var planet_spawner_gaseous_scene: PackedScene
var asteroid_field_scene: PackedScene
var station_scene: PackedScene

# Generation tracking
var _generated_cells: Dictionary = {}  # cell_coords (string) -> { planets: [], asteroids: [], stations: [] }
var _entity_counts: Dictionary = {
	"terran_planet": 0,
	"gaseous_planet": 0,
	"asteroid_field": 0,
	"station": 0
}

# Planet spawner instances for tracking and management
var _planet_spawners: Dictionary = {}  # cell_key -> planet_spawner

# Proximity tracking
var _planet_cells: Array[Vector2i] = []  # Cells containing planets
var _proximity_excluded_cells: Dictionary = {}  # Cell coords (string) -> bool

# Debug mode
var debug_mode: bool = false

# Seed offset constants - used to ensure different entity types get different seeds
const PLANET_SEED_OFFSET = 1000000  # Base offset for planets
const ASTEROID_SEED_OFFSET = 2000000  # Base offset for asteroid fields
const STATION_SEED_OFFSET = 3000000  # Base offset for stations
const TERRAN_TYPE_OFFSET = 10000  # Offset for terran planet types
const GASEOUS_TYPE_OFFSET = 20000  # Offset for gas giant types

# Initialization
func _ready() -> void:
	# Find GameSettings in the main scene
	var main_scene = get_tree().current_scene
	game_settings = main_scene.get_node_or_null("GameSettings")
	
	# Check debug status
	if game_settings:
		# Connect to debug settings changes
		if not game_settings.is_connected("debug_settings_changed", _on_debug_settings_changed):
			game_settings.connect("debug_settings_changed", _on_debug_settings_changed)
		
		# Set initial debug state
		debug_mode = game_settings.debug_mode and game_settings.debug_world_generator
	
	# Get a reference to SeedManager
	if Engine.has_singleton("SeedManager"):
		seed_manager = Engine.get_singleton("SeedManager")
		
		# Wait for SeedManager to be fully initialized
		if not seed_manager.is_initialized and seed_manager.has_signal("seed_initialized"):
			await seed_manager.seed_initialized
	
	# Load required scenes if not set
	_initialize_scenes()
	
	# Debug output
	debug_print("Initialized with game seed " + str(game_settings.get_seed() if game_settings else "N/A"))

# Handler for debug settings changes
func _on_debug_settings_changed(debug_settings: Dictionary) -> void:
	debug_mode = debug_settings.get("master", false) and debug_settings.get("world_generator", false)
	
	if debug_mode:
		debug_print("Debug mode enabled")
		# Print current state
		debug_print("Current world state: " + str(_entity_counts))

# Utility debug print
func debug_print(message: String) -> void:
	if debug_mode:
		if Engine.has_singleton("DebugLogger"):
			DebugLogger.debug("WorldGenerator", message)
		else:
			print("WorldGenerator: " + message)

# Initialize required scenes
func _initialize_scenes() -> void:
	# Load Terran Planet Spawner scene
	if planet_spawner_terran_scene == null:
		var terran_path = "res://scenes/world/planet_spawner_terran.tscn"
		if ResourceLoader.exists(terran_path):
			planet_spawner_terran_scene = load(terran_path)
	
	# Load Gaseous Planet Spawner scene
	if planet_spawner_gaseous_scene == null:
		var gaseous_path = "res://scenes/world/planet_spawner_gaseous.tscn"
		if ResourceLoader.exists(gaseous_path):
			planet_spawner_gaseous_scene = load(gaseous_path)
	
	# Load asteroid field scene
	if asteroid_field_scene == null:
		var asteroid_path = "res://scenes/world/asteroid_field.tscn"
		if ResourceLoader.exists(asteroid_path):
			asteroid_field_scene = load(asteroid_path)
	
	# Load station scene
	if station_scene == null:
		var station_path = "res://scenes/world/station.tscn"
		if ResourceLoader.exists(station_path):
			station_scene = load(station_path)

# Generate a complete starter world based on GameSettings
func generate_starter_world() -> Dictionary:
	# Clear any existing world
	clear_world()
	
	# Emit signal that generation has started
	world_generation_started.emit()
	
	# Reset tracking
	_planet_cells.clear()
	_proximity_excluded_cells.clear()
	_planet_spawners.clear()
	
	# Generate first terran planet randomly (this will be player's starting planet)
	var player_planet_cell = generate_random_terran_planet(1)  # 1 is proximity value
	
	# Generate gaseous planets - respect count from GameSettings
	var total_gaseous_planets = game_settings.gaseous_planets if game_settings else 1
	var gaseous_planet_cell = Vector2i(-1, -1)
	
	# Always spawn at least one gaseous planet
	if total_gaseous_planets > 0:
		gaseous_planet_cell = generate_gaseous_planet(2)
		
		# Generate remaining gaseous planets (if any)
		for i in range(1, total_gaseous_planets):
			generate_gaseous_planet(2)
	
	# Calculate maximum planets that could fit in the grid
	var max_planets = calculate_max_planets()
	
	# Generate remaining terran planets - respect count from GameSettings
	var total_terran_planets = game_settings.terran_planets if game_settings else 5
	
	# We already spawned the first terran planet, so generate the remaining ones
	for i in range(1, total_terran_planets):
		# Only proceed if we haven't hit the maximum
		if _entity_counts.terran_planet + _entity_counts.gaseous_planet < max_planets:
			generate_random_terran_planet(1)
		else:
			debug_print("Maximum planet limit reached, stopping planet generation.")
			break
	
	# Generate asteroid fields
	var asteroid_count = game_settings.asteroid_fields if game_settings else 0
	for i in range(asteroid_count):
		generate_asteroid_field()
	
	# Generate stations
	var station_count = game_settings.space_stations if game_settings else 0
	for i in range(station_count):
		generate_station()
	
	# Emit signal that generation is complete
	world_generation_completed.emit()
	
	# Debug output
	debug_print("Starter world generation complete")
	debug_print("- Player planet at cell: " + str(player_planet_cell))
	debug_print("- Total terran planets: " + str(_entity_counts.terran_planet) + 
				"/" + str(total_terran_planets))
	debug_print("- Total gaseous planets: " + str(_entity_counts.gaseous_planet) + 
				"/" + str(total_gaseous_planets))
	debug_print("- Maximum possible planets: " + str(max_planets))
	debug_print("- Total asteroid fields: " + str(_entity_counts.asteroid_field))
	debug_print("- Total stations: " + str(_entity_counts.station))
	
	# Return the cells where the planets were generated
	return {
		"player_planet_cell": player_planet_cell,
		"gaseous_planet_cell": gaseous_planet_cell
	}

# Calculate maximum number of planets that could fit in the grid given proximity rules
func calculate_max_planets() -> int:
	# Start with total number of cells in the grid
	var total_cells = game_settings.grid_size * game_settings.grid_size if game_settings else 25
	var available_cells = total_cells
	
	# Count excluded cells
	available_cells -= _proximity_excluded_cells.size()
	
	# Return planets already placed plus available cell count
	return _entity_counts.terran_planet + _entity_counts.gaseous_planet + available_cells

# Generate consistent seed for a cell and entity type
# Standardized approach for deterministic object ID generation
func _generate_entity_seed(cell: Vector2i, entity_type: String, subtype_index: int = 0) -> int:
	# Base seed comes from GameSettings or SeedManager
	var base_seed = 0
	if game_settings:
		base_seed = game_settings.get_seed()
	elif seed_manager:
		base_seed = seed_manager.get_seed()
	else:
		base_seed = get_instance_id()  # Last resort fallback
	
	# Apply entity type offset to ensure different types get different seeds
	var type_offset = 0
	match entity_type:
		"terran_planet":
			type_offset = PLANET_SEED_OFFSET + TERRAN_TYPE_OFFSET
		"gaseous_planet":
			type_offset = PLANET_SEED_OFFSET + GASEOUS_TYPE_OFFSET
		"asteroid_field":
			type_offset = ASTEROID_SEED_OFFSET
		"station":
			type_offset = STATION_SEED_OFFSET
		_:
			type_offset = 0
	
	# Cell position is encoded with different multipliers for x and y
	# This ensures different cells get different seeds
	var cell_offset = (cell.x * 1000) + (cell.y * 100)
	
	# Subtype index allows for generating multiple entities of same type in same cell
	var subtype_offset = subtype_index * 10
	
	# Combine all factors to create a unique but deterministic seed
	return base_seed + type_offset + cell_offset + subtype_offset

# Deterministically shuffle candidate cells
func _shuffle_candidates(candidate_cells: Array) -> void:
	if seed_manager:
		# Use SeedManager for consistent shuffling
		seed_manager.shuffle_array(candidate_cells, get_instance_id())
	else:
		# Fallback to deterministic local shuffling
		var seed_value = game_settings.get_seed() if game_settings else get_instance_id()
		var temp_rng = RandomNumberGenerator.new()
		temp_rng.seed = seed_value
		
		# Manual Fisher-Yates shuffle
		for i in range(candidate_cells.size() - 1, 0, -1):
			var j = temp_rng.randi_range(0, i)
			var temp = candidate_cells[i]
			candidate_cells[i] = candidate_cells[j]
			candidate_cells[j] = temp

# Generate a gaseous planet in a random grid cell
func generate_gaseous_planet(proximity: int = 2) -> Vector2i:
	# Check if we have the required scene
	if not planet_spawner_gaseous_scene:
		push_error("WorldGenerator: planet_spawner_gaseous_scene not loaded")
		return Vector2i(-1, -1)
	
	# Start with a list of all possible cells
	var candidate_cells = []
	if game_settings:
		for x in range(game_settings.grid_size):
			for y in range(game_settings.grid_size):
				var cell = Vector2i(x, y)
				# Skip cells that are excluded due to proximity
				var cell_key = get_cell_key(cell)
				if _proximity_excluded_cells.has(cell_key):
					continue
				candidate_cells.append(cell)
	else:
		# Fallback if no game settings
		for x in range(5):
			for y in range(5):
				var cell = Vector2i(x, y)
				var cell_key = get_cell_key(cell)
				if _proximity_excluded_cells.has(cell_key):
					continue
				candidate_cells.append(cell)
	
	# Shuffle the cells using deterministic method
	_shuffle_candidates(candidate_cells)
	
	# Try to place a gaseous planet in one of the shuffled cells
	for cell in candidate_cells:
		# Skip if this cell already has content
		if is_cell_generated(cell):
			continue
		
		# Generate a deterministic seed for this cell and entity type
		var cell_seed = _generate_entity_seed(cell, "gaseous_planet")
		var seed_offset = cell_seed - (game_settings.get_seed() if game_settings else 0)
		
		# Create a planet spawner for this cell
		var planet_spawner = planet_spawner_gaseous_scene.instantiate()
		
		# Randomize the gas giant type using our standardized approach
		var gas_giant_type = 0
		if seed_manager:
			# Generate a random int using the cell seed
			# This ensures the same cell always generates the same planet type
			gas_giant_type = seed_manager.get_random_int(cell_seed, 0, 3)  # 0-3 are gas giant types
		else:
			# Fallback deterministic approach
			var temp_rng = RandomNumberGenerator.new()
			temp_rng.seed = cell_seed
			gas_giant_type = temp_rng.randi_range(0, 3)
		
		# Add to scene and configure
		add_child(planet_spawner)
		planet_spawner.gaseous_theme = gas_giant_type + 1  # +1 because 0 is Random
		
		# Configure the spawner using its API
		planet_spawner.set_grid_position(cell.x, cell.y)
		planet_spawner.use_grid_position = true
		planet_spawner.local_seed_offset = seed_offset
		
		# Spawn the planet
		var planet = planet_spawner.spawn_planet()
		
		if not planet:
			push_error("WorldGenerator: Failed to spawn gaseous planet at ", cell)
			planet_spawner.queue_free()
			continue
		
		# Connect to planet spawner signals if available
		if planet_spawner.has_signal("planet_spawned"):
			if not planet_spawner.is_connected("planet_spawned", _on_planet_spawned):
				planet_spawner.planet_spawned.connect(_on_planet_spawned)
		
		# Initialize cell tracking if needed
		var cell_key = get_cell_key(cell)
		if not _generated_cells.has(cell_key):
			_generated_cells[cell_key] = {
				"planets": [],
				"asteroid_fields": [],
				"stations": []
			}
		
		# Store the spawner
		_planet_spawners[cell_key] = planet_spawner
		
		# Track this planet
		_generated_cells[cell_key].planets.append(planet_spawner)
		_entity_counts.gaseous_planet += 1
		
		# Mark proximity cells as excluded
		mark_proximity_cells(cell, proximity, _proximity_excluded_cells)
		
		# Mark this cell as having a planet
		_planet_cells.append(cell)
		
		# Emit signal
		entity_generated.emit(planet, "gaseous_planet", cell)
		
		debug_print("Generated gaseous planet at cell " + str(cell))
		
		return cell
	
	# If we reach here, we couldn't place a gaseous planet
	push_warning("WorldGenerator: Failed to generate gaseous planet - no valid cells available")
	return Vector2i(-1, -1)

# Generate a random terran planet in a random grid cell
func generate_random_terran_planet(proximity: int = 1) -> Vector2i:
	# Check if we have the required scene
	if not planet_spawner_terran_scene:
		push_error("WorldGenerator: planet_spawner_terran_scene not loaded")
		return Vector2i(-1, -1)
	
	# Start with a list of all possible cells
	var candidate_cells = []
	if game_settings:
		for x in range(game_settings.grid_size):
			for y in range(game_settings.grid_size):
				var cell = Vector2i(x, y)
				# Skip cells that are excluded due to proximity
				var cell_key = get_cell_key(cell)
				if _proximity_excluded_cells.has(cell_key):
					continue
				candidate_cells.append(cell)
	else:
		# Fallback if no game settings
		for x in range(5):
			for y in range(5):
				var cell = Vector2i(x, y)
				var cell_key = get_cell_key(cell)
				if _proximity_excluded_cells.has(cell_key):
					continue
				candidate_cells.append(cell)
	
	# Shuffle the cells using deterministic method
	_shuffle_candidates(candidate_cells)
	
	# Try to place a terran planet in one of the shuffled cells
	for cell in candidate_cells:
		# Skip if this cell already has content
		if is_cell_generated(cell):
			continue
		
		# Generate a deterministic seed for this cell and entity type
		var cell_seed = _generate_entity_seed(cell, "terran_planet")
		var seed_offset = cell_seed - (game_settings.get_seed() if game_settings else 0)
		
		# Create a planet spawner for this cell
		var planet_spawner = planet_spawner_terran_scene.instantiate()
		
		# Get the appropriate planet type
		var terran_type = 0
		if _entity_counts.terran_planet == 0 and game_settings:
			# First terran planet (player's starting planet)
			terran_type = game_settings.player_starting_planet_type
		else:
			# Random planet type using SeedManager if available
			if seed_manager:
				terran_type = seed_manager.get_random_int(cell_seed, 0, 6)  # 0-6 are terran types
			else:
				# Fallback deterministic approach
				var temp_rng = RandomNumberGenerator.new()
				temp_rng.seed = cell_seed
				terran_type = temp_rng.randi_range(0, 6)
				
			if game_settings and terran_type == game_settings.player_starting_planet_type:
				terran_type = (terran_type + 1) % 7  # Skip to next type
		
		# Add to scene and configure
		add_child(planet_spawner)
		planet_spawner.terran_theme = terran_type + 1  # +1 because 0 is Random
		
		# Configure the spawner
		planet_spawner.set_grid_position(cell.x, cell.y)
		planet_spawner.use_grid_position = true
		planet_spawner.local_seed_offset = seed_offset
		
		# Spawn the planet
		var planet = planet_spawner.spawn_planet()
		
		if not planet:
			push_error("WorldGenerator: Failed to spawn terran planet at ", cell)
			planet_spawner.queue_free()
			continue
		
		# Connect to planet spawner signals if available
		if planet_spawner.has_signal("planet_spawned"):
			if not planet_spawner.is_connected("planet_spawned", _on_planet_spawned):
				planet_spawner.planet_spawned.connect(_on_planet_spawned)
		
		# Initialize cell tracking if needed
		var cell_key = get_cell_key(cell)
		if not _generated_cells.has(cell_key):
			_generated_cells[cell_key] = {
				"planets": [],
				"asteroid_fields": [],
				"stations": []
			}
		
		# Store the spawner
		_planet_spawners[cell_key] = planet_spawner
		
		# Track this planet
		_generated_cells[cell_key].planets.append(planet_spawner)
		_entity_counts.terran_planet += 1
		
		# Mark proximity cells as excluded
		mark_proximity_cells(cell, proximity, _proximity_excluded_cells)
		
		# Mark this cell as having a planet
		_planet_cells.append(cell)
		
		# Emit signal
		entity_generated.emit(planet, "terran_planet", cell)
		
		debug_print("Generated terran planet at cell " + str(cell))
		if _entity_counts.terran_planet == 1:
			debug_print("This is the player's starting planet (" + 
					  game_settings.get_planet_type_name(terran_type) + ")")
		
		return cell
	
	# If we reach here, we couldn't place a terran planet
	push_warning("WorldGenerator: Failed to generate terran planet - no valid cells available")
	return Vector2i(-1, -1)

# Generate an asteroid field in a random cell
func generate_asteroid_field() -> Vector2i:
	if asteroid_field_scene == null:
		push_error("WorldGenerator: asteroid_field_scene not loaded")
		return Vector2i(-1, -1)
	
	# Get a list of valid cells for asteroid fields
	var candidate_cells = []
	if game_settings:
		for x in range(game_settings.grid_size):
			for y in range(game_settings.grid_size):
				var cell = Vector2i(x, y)
				if not is_cell_generated(cell):
					candidate_cells.append(cell)
	else:
		# Fallback if no game settings
		for x in range(5):
			for y in range(5):
				var cell = Vector2i(x, y)
				if not is_cell_generated(cell):
					candidate_cells.append(cell)
	
	# Shuffle the cells using deterministic method
	_shuffle_candidates(candidate_cells)
	
	# Try to place an asteroid field in one of the shuffled cells
	for cell in candidate_cells:
		# Generate a deterministic seed for this asteroid field
		var field_seed = _generate_entity_seed(cell, "asteroid_field")
		
		# Create an asteroid field
		var asteroid_field = asteroid_field_scene.instantiate()
		add_child(asteroid_field)
		
		# Position the asteroid field
		var world_pos
		if game_settings:
			world_pos = game_settings.get_cell_world_position(cell)
		else:
			world_pos = Vector2(cell.x * 1024, cell.y * 1024)
		asteroid_field.global_position = world_pos
		
		# Configure the asteroid field if it has the appropriate methods
		if asteroid_field.has_method("generate"):
			# Add some randomization to density and size using SeedManager
			var density = 1.0
			var size = 1.0
			
			if seed_manager:
				# Use standardized seed generation
				density = seed_manager.get_random_value(field_seed, 0.5, 1.5)
				size = seed_manager.get_random_value(field_seed + 1, 0.7, 1.3)
			else:
				# Fallback to local deterministic RNG
				var temp_rng = RandomNumberGenerator.new()
				temp_rng.seed = field_seed
				density = temp_rng.randf_range(0.5, 1.5)
				size = temp_rng.randf_range(0.7, 1.3)
			
			asteroid_field.generate(field_seed, density, size)
		
		# Track this asteroid field
		var cell_key = get_cell_key(cell)
		if not _generated_cells.has(cell_key):
			_generated_cells[cell_key] = {
				"planets": [],
				"asteroid_fields": [],
				"stations": []
			}
		_generated_cells[cell_key].asteroid_fields.append(asteroid_field)
		_entity_counts.asteroid_field += 1
		
		# Register with EntityManager if available
		if has_node("/root/EntityManager") and EntityManager.has_method("register_entity"):
			EntityManager.register_entity(asteroid_field, "asteroid_field")
		
		# Emit signal
		entity_generated.emit(asteroid_field, "asteroid_field", cell)
		
		debug_print("Generated asteroid field at cell " + str(cell))
		
		return cell
	
	# If we reach here, we couldn't place an asteroid field
	push_warning("WorldGenerator: Failed to generate asteroid field - no valid cells available")
	return Vector2i(-1, -1)

# Generate a station in a random cell
func generate_station() -> Vector2i:
	if station_scene == null:
		push_error("WorldGenerator: station_scene not loaded")
		return Vector2i(-1, -1)
	
	# Get a list of valid cells for stations
	var candidate_cells = []
	if game_settings:
		for x in range(game_settings.grid_size):
			for y in range(game_settings.grid_size):
				var cell = Vector2i(x, y)
				if not is_cell_generated(cell):
					candidate_cells.append(cell)
	else:
		# Fallback if no game settings
		for x in range(5):
			for y in range(5):
				var cell = Vector2i(x, y)
				if not is_cell_generated(cell):
					candidate_cells.append(cell)
	
	# Shuffle the cells using deterministic method
	_shuffle_candidates(candidate_cells)
	
	# Try to place a station in one of the shuffled cells
	for cell in candidate_cells:
		# Generate a deterministic seed for this station
		var station_seed = _generate_entity_seed(cell, "station")
		
		# Create a station
		var station = station_scene.instantiate()
		add_child(station)
		
		# Position the station
		var world_pos
		if game_settings:
			world_pos = game_settings.get_cell_world_position(cell)
		else:
			world_pos = Vector2(cell.x * 1024, cell.y * 1024)
		station.global_position = world_pos
		
		# Add slight position variation within the cell using SeedManager
		var cell_size = game_settings.grid_cell_size if game_settings else 1024
		var offset = Vector2.ZERO
		
		if seed_manager:
			# Use standardized seed generation with small variations for position x/y
			offset = Vector2(
				seed_manager.get_random_value(station_seed, -cell_size/4.0, cell_size/4.0),
				seed_manager.get_random_value(station_seed + 1, -cell_size/4.0, cell_size/4.0)
			)
		else:
			# Fallback to local deterministic RNG
			var temp_rng = RandomNumberGenerator.new()
			temp_rng.seed = station_seed
			offset = Vector2(
				temp_rng.randf_range(-cell_size/4.0, cell_size/4.0),
				temp_rng.randf_range(-cell_size/4.0, cell_size/4.0)
			)
			
		station.global_position += offset
		
		# Configure the station if it has an initialize method
		if station.has_method("initialize"):
			station.initialize(station_seed)
		
		# Track this station
		var cell_key = get_cell_key(cell)
		if not _generated_cells.has(cell_key):
			_generated_cells[cell_key] = {
				"planets": [],
				"asteroid_fields": [],
				"stations": []
			}
		_generated_cells[cell_key].stations.append(station)
		_entity_counts.station += 1
		
		# Register with EntityManager if available
		if has_node("/root/EntityManager") and EntityManager.has_method("register_entity"):
			EntityManager.register_entity(station, "station")
		
		# Emit signal
		entity_generated.emit(station, "station", cell)
		
		debug_print("Generated station at cell " + str(cell))
		
		return cell
	
	# If we reach here, we couldn't place a station
	push_warning("WorldGenerator: Failed to generate station - no valid cells available")
	return Vector2i(-1, -1)

# Callback for planet spawner signals
func _on_planet_spawned(planet_instance) -> void:
	# Register the planet with EntityManager if available
	if has_node("/root/EntityManager") and EntityManager.has_method("register_entity"):
		EntityManager.register_entity(planet_instance, "planet")

# Mark cells within proximity as excluded
func mark_proximity_cells(center: Vector2i, proximity: int, excluded_dict: Dictionary) -> void:
	if proximity <= 0:
		# Only exclude the center cell with proximity 0
		excluded_dict[get_cell_key(center)] = true
		return
	
	# Exclude cells in a square around the center
	for dx in range(-proximity, proximity + 1):
		for dy in range(-proximity, proximity + 1):
			var cell = Vector2i(center.x + dx, center.y + dy)
			
			# Only exclude cells that are within the grid
			if is_valid_cell(cell):
				excluded_dict[get_cell_key(cell)] = true

# Clear all generated world content
func clear_world() -> void:
	# Clean up all generated entities
	for cell_key in _generated_cells:
		var cell_data = _generated_cells[cell_key]
		
		# Clear planets via their spawners
		for planet_spawner in cell_data.planets:
			if is_instance_valid(planet_spawner):
				planet_spawner.queue_free()
		
		# Clear asteroid fields
		for asteroid_field in cell_data.asteroid_fields:
			if is_instance_valid(asteroid_field):
				asteroid_field.queue_free()
		
		# Clear stations
		for station in cell_data.stations:
			if is_instance_valid(station):
				# Deregister with EntityManager if available
				if has_node("/root/EntityManager") and EntityManager.has_method("deregister_entity"):
					EntityManager.deregister_entity(station)
				station.queue_free()
	
	# Reset tracking
	_generated_cells.clear()
	_entity_counts = {
		"terran_planet": 0,
		"gaseous_planet": 0,
		"asteroid_field": 0,
		"station": 0
	}
	
	# Reset proximity tracking
	_planet_cells.clear()
	_proximity_excluded_cells.clear()
	_planet_spawners.clear()
	
	# Debug output
	debug_print("World cleared")

# Check if a cell is valid (within grid bounds)
func is_valid_cell(cell_coords: Vector2i) -> bool:
	if not game_settings:
		return 0 <= cell_coords.x and cell_coords.x < 5 and 0 <= cell_coords.y and cell_coords.y < 5
	
	return (
		cell_coords.x >= 0 and cell_coords.x < game_settings.grid_size and
		cell_coords.y >= 0 and cell_coords.y < game_settings.grid_size
	)

# Helper method to get a consistent cell key
func get_cell_key(cell_coords: Vector2i) -> String:
	return str(cell_coords.x) + "," + str(cell_coords.y)

# Check if a cell has been generated
func is_cell_generated(cell_coords: Vector2i) -> bool:
	var cell_key = get_cell_key(cell_coords)
	return _generated_cells.has(cell_key) and (
		not _generated_cells[cell_key].planets.is_empty() or
		not _generated_cells[cell_key].asteroid_fields.is_empty() or
		not _generated_cells[cell_key].stations.is_empty()
	)

# Get all generated entities in a cell
func get_cell_entities(cell_coords: Vector2i) -> Array:
	var cell_key = get_cell_key(cell_coords)
	var result = []
	
	if not _generated_cells.has(cell_key):
		return result
	
	var cell_data = _generated_cells[cell_key]
	
	# Add planets (get actual planet instances from spawners)
	for planet_spawner in cell_data.planets:
		if is_instance_valid(planet_spawner) and planet_spawner.has_method("get_planet_instance"):
			var planet = planet_spawner.get_planet_instance()
			if planet:
				result.append(planet)
	
	# Add asteroid fields
	for asteroid_field in cell_data.asteroid_fields:
		if is_instance_valid(asteroid_field):
			result.append(asteroid_field)
	
	# Add stations
	for station in cell_data.stations:
		if is_instance_valid(station):
			result.append(station)
	
	return result
