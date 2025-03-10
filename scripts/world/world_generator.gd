# scripts/world/world_generator.gd
# ========================
# Purpose:
#   Procedurally generates the game world based on GameSettings
#   Handles spawning of planets, asteroids, and stations
#   Maintains consistent generation based on the game seed
#   Enforces planet proximity constraints

extends Node
class_name WorldGenerator

signal world_generation_started
signal world_generation_completed
signal entity_generated(entity, type, cell)

# References to required components
var game_settings: GameSettings = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Scene references
@export var planet_spawner_terran_scene: PackedScene
@export var planet_spawner_gaseous_scene: PackedScene
@export var asteroid_field_scene: PackedScene
@export var station_scene: PackedScene

# Generation tracking
var _generated_cells: Dictionary = {}  # cell_coords (string) -> { planets: [], asteroids: [], stations: [] }
var _entity_counts: Dictionary = {
	"planet": 0,
	"asteroid_field": 0,
	"station": 0
}

# Planet spawner instances for tracking and management
var _planet_spawners: Dictionary = {}  # cell_key -> planet_spawner

# Proximity tracking
var _planet_cells: Array[Vector2i] = []  # Cells containing planets
var _proximity_excluded_cells: Dictionary = {}  # Cell coords (string) -> bool

# Initialization
func _ready() -> void:
	# Find GameSettings in the main scene
	var main_scene = get_tree().current_scene
	game_settings = main_scene.get_node_or_null("GameSettings")
	
	# Load required scenes if not set
	_initialize_scenes()
	
	# Debug output
	if game_settings and game_settings.debug_mode:
		print("WorldGenerator: Initialized with game seed ", game_settings.get_seed())

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
	
	if asteroid_field_scene == null:
		var asteroid_path = "res://scenes/world/asteroid_field.tscn"
		if ResourceLoader.exists(asteroid_path):
			asteroid_field_scene = load(asteroid_path)
	
	if station_scene == null:
		var station_path = "res://scenes/world/station.tscn"
		if ResourceLoader.exists(station_path):
			station_scene = load(station_path)

# Generate a starter world with exactly one gaseous planet and one lush planet
func generate_starter_world() -> Dictionary:
	# Clear any existing world
	clear_world()
	
	# Emit signal that generation has started
	world_generation_started.emit()
	
	# Initialize RNG with game seed
	_rng.seed = game_settings.get_seed()
	
	# Reset tracking
	_planet_cells.clear()
	_proximity_excluded_cells.clear()
	_planet_spawners.clear()
	
	# Generate gaseous planet with proximity constraint of 2
	var gaseous_planet_cell = generate_gaseous_planet(2)
	
	# Generate lush planet with proximity constraint of 1
	var lush_planet_cell = generate_lush_planet(1)
	
	# Generate remaining cells (asteroids, stations, etc.)
	for x in range(game_settings.grid_size):
		for y in range(game_settings.grid_size):
			var cell = Vector2i(x, y)
			var cell_key = get_cell_key(cell)
			
			# Skip cells that already have planets
			if _generated_cells.has(cell_key) and not _generated_cells[cell_key].planets.is_empty():
				continue
			
			# Generate other content in this cell
			generate_cell_content_except_planets(cell)
	
	# Emit signal that generation is complete
	world_generation_completed.emit()
	
	# Debug output
	if game_settings and game_settings.debug_mode:
		print("WorldGenerator: Starter world generation complete")
		print("- Gaseous planet at cell: ", gaseous_planet_cell)
		print("- Lush planet at cell: ", lush_planet_cell)
	
	# Return the cells where the planets were generated
	return {
		"gaseous_planet_cell": gaseous_planet_cell,
		"lush_planet_cell": lush_planet_cell
	}

# Generate a gaseous planet in a random grid cell
func generate_gaseous_planet(proximity: int = 2) -> Vector2i:
	# Start with a list of all possible cells
	var candidate_cells = []
	for x in range(game_settings.grid_size):
		for y in range(game_settings.grid_size):
			var cell = Vector2i(x, y)
			# Skip player starting cell
			if cell == game_settings.player_starting_cell:
				continue
			candidate_cells.append(cell)
	
	# Shuffle the cells for random distribution
	candidate_cells.shuffle_with_seed(game_settings.get_seed())
	
	# Try to place a gaseous planet in one of the shuffled cells
	for cell in candidate_cells:
		# Skip if this cell already has content
		if is_cell_generated(cell):
			continue
			
		# Skip if this cell is excluded due to proximity
		var cell_key = get_cell_key(cell)
		if _proximity_excluded_cells.has(cell_key):
			continue
		
		# Set up the cell seed
		var cell_seed = game_settings.get_seed() + (cell.x * 1000) + (cell.y * 100)
		var seed_offset = cell_seed - game_settings.get_seed()
		
		# Create a planet spawner for this cell
		var planet_spawner
		
		if planet_spawner_gaseous_scene:
			planet_spawner = planet_spawner_gaseous_scene.instantiate()
		else:
			planet_spawner = PlanetSpawnerGaseous.new()
			
		# Randomize the gas giant type
		_rng.seed = cell_seed
		var gas_giant_type = _rng.randi_range(0, 3)  # 0-3 are the gas giant types
		
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
		_entity_counts.planet += 1
		
		# Mark proximity cells as excluded
		mark_proximity_cells(cell, proximity, _proximity_excluded_cells)
		
		# Mark this cell as having a planet
		_planet_cells.append(cell)
		
		# Emit signal
		entity_generated.emit(planet, "planet", cell)
		
		if game_settings and game_settings.debug_mode:
			print("WorldGenerator: Generated gaseous planet at cell ", cell)
		
		return cell
	
	# If we reach here, we couldn't place a gaseous planet
	push_error("WorldGenerator: Failed to generate gaseous planet")
	return Vector2i(-1, -1)

# Generate a lush planet in a random grid cell
func generate_lush_planet(proximity: int = 1) -> Vector2i:
	# Start with a list of all possible cells
	var candidate_cells = []
	for x in range(game_settings.grid_size):
		for y in range(game_settings.grid_size):
			var cell = Vector2i(x, y)
			# Skip cells that are excluded due to proximity with other planets
			var cell_key = get_cell_key(cell)
			if _proximity_excluded_cells.has(cell_key):
				continue
			# Skip cells that already have content
			if is_cell_generated(cell):
				continue
			candidate_cells.append(cell)
	
	# Shuffle the cells for random distribution
	candidate_cells.shuffle_with_seed(game_settings.get_seed() + 123) # Different seed than gaseous planet
	
	# Try to place a lush planet in one of the shuffled cells
	for cell in candidate_cells:
		# Set up the cell seed
		var cell_seed = game_settings.get_seed() + (cell.x * 1000) + (cell.y * 100)
		var seed_offset = cell_seed - game_settings.get_seed()
		
		# Create a planet spawner for this cell
		var planet_spawner
		
		if planet_spawner_terran_scene:
			planet_spawner = planet_spawner_terran_scene.instantiate()
		else:
			planet_spawner = PlanetSpawnerTerran.new()
			
		# Force the planet to be Lush (theme index 3)
		add_child(planet_spawner)
		planet_spawner.terran_theme = 4  # 4 = Lush (index 3 + 1 because 0 is Random)
		
		# Configure the spawner
		planet_spawner.set_grid_position(cell.x, cell.y)
		planet_spawner.use_grid_position = true
		planet_spawner.local_seed_offset = seed_offset
		
		# Spawn the planet
		var planet = planet_spawner.spawn_planet()
		
		if not planet:
			push_error("WorldGenerator: Failed to spawn lush planet at ", cell)
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
		_entity_counts.planet += 1
		
		# Mark proximity cells as excluded
		mark_proximity_cells(cell, proximity, _proximity_excluded_cells)
		
		# Mark this cell as having a planet
		_planet_cells.append(cell)
		
		# Emit signal
		entity_generated.emit(planet, "planet", cell)
		
		if game_settings and game_settings.debug_mode:
			print("WorldGenerator: Generated lush planet at cell ", cell)
		
		return cell
	
	# If we reach here, we couldn't place a lush planet
	push_error("WorldGenerator: Failed to generate lush planet")
	return Vector2i(-1, -1)

# Generate the entire world based on game settings
func generate_world() -> void:
	if not game_settings:
		push_error("WorldGenerator: Cannot generate world - GameSettings not found")
		return
	
	# Clear any existing world
	clear_world()
	
	# Emit signal that generation has started
	world_generation_started.emit()
	
	# Initialize RNG with game seed
	_rng.seed = game_settings.get_seed()
	
	# Reset proximity tracking
	_planet_cells.clear()
	_proximity_excluded_cells.clear()
	_planet_spawners.clear()
	
	# Calculate max planets that can fit with proximity setting
	var max_planets_capped = calculate_max_planets()
	var effective_max_planets = min(game_settings.max_planets, max_planets_capped)
	
	# Debug output for max planets
	if game_settings.debug_mode:
		print("WorldGenerator: Max planets capped to ", effective_max_planets, 
			  " (original setting: ", game_settings.max_planets, 
			  ", max possible with proximity ", game_settings.planet_proximity, ": ", 
			  max_planets_capped, ")")
	
	# Generate planets with strategic placement
	var planets_placed = generate_planets_with_proximity(effective_max_planets)
	
	# Generate remaining cells (asteroids, stations, etc.)
	for x in range(game_settings.grid_size):
		for y in range(game_settings.grid_size):
			var cell = Vector2i(x, y)
			var cell_key = get_cell_key(cell)
			
			# Skip cells that already have planets
			if _generated_cells.has(cell_key) and not _generated_cells[cell_key].planets.is_empty():
				continue
			
			# Generate other content in this cell
			generate_cell_content_except_planets(cell)
	
	# Emit signal that generation is complete
	world_generation_completed.emit()
	
	# Debug output
	if game_settings.debug_mode:
		print("WorldGenerator: World generation complete")
		print("- Planets: ", _entity_counts.planet, " of ", effective_max_planets, " (requested: ", game_settings.max_planets, ")")
		print("- Asteroid Fields: ", _entity_counts.asteroid_field)
		print("- Stations: ", _entity_counts.station)

# Calculate maximum planets that could fit with proximity constraints
func calculate_max_planets() -> int:
	if not game_settings or game_settings.grid_size <= 0:
		return 0
	
	var proximity = game_settings.planet_proximity
	
	# In a perfect grid arrangement with proximity p:
	# Each planet requires a square of size (2p+1)×(2p+1) cells
	# So the maximum planets would be: ⌊grid_size²/((2p+1)²)⌋
	var effective_spacing = (2 * proximity + 1)
	var theoretical_max = int(floor(pow(game_settings.grid_size, 2) / pow(effective_spacing, 2)))
	
	# Adjust for edge effects and grid size not being multiple of spacing
	if proximity > 0:
		# Simulate actual placement to get a more accurate count
		var max_count = simulate_max_planets(proximity)
		return max_count
	else:
		# With proximity 0, all cells could have planets
		return game_settings.grid_size * game_settings.grid_size

# Simulate planet placement to find maximum count
func simulate_max_planets(proximity: int) -> int:
	var temp_cells = []
	var temp_excluded = {}
	var count = 0
	
	# Try to place in a grid pattern (most efficient)
	var spacing = 2 * proximity + 1
	
	for x in range(0, game_settings.grid_size, spacing):
		for y in range(0, game_settings.grid_size, spacing):
			var cell = Vector2i(x, y)
			
			# Check if cell is within grid
			if is_valid_cell(cell):
				# Skip player starting cell
				if cell == game_settings.player_starting_cell:
					continue
					
				temp_cells.append(cell)
				count += 1
				
				# Mark proximity cells as excluded
				mark_proximity_cells(cell, proximity, temp_excluded)
	
	return count

# Generate planets respecting proximity constraints
func generate_planets_with_proximity(max_planets: int) -> int:
	if not game_settings:
		return 0
	
	# Start with a list of all possible cells
	var candidate_cells = []
	for x in range(game_settings.grid_size):
		for y in range(game_settings.grid_size):
			var cell = Vector2i(x, y)
			# Skip player starting cell
			if cell == game_settings.player_starting_cell:
				continue
			candidate_cells.append(cell)
	
	# Shuffle the cells for random distribution
	candidate_cells.shuffle_with_seed(game_settings.get_seed())
	
	var planets_placed = 0
	var proximity = game_settings.planet_proximity
	
	# Place planets in the shuffled cells
	for cell in candidate_cells:
		if planets_placed >= max_planets:
			break
		
		var cell_key = get_cell_key(cell)
		
		# Skip if this cell is excluded due to proximity or already has content
		if _proximity_excluded_cells.has(cell_key) or is_cell_generated(cell):
			continue
		
		# Check planet chance
		var cell_seed = game_settings.get_seed() + (cell.x * 1000) + (cell.y * 100)
		_rng.seed = cell_seed
		var planet_roll = _rng.randi_range(1, 100)
		
		if planet_roll <= game_settings.planet_chance_per_cell:
			# Create a planet spawner for this cell
			var planet_spawner = create_planet_spawner(cell)
			if planet_spawner:
				planets_placed += 1
				
				# Mark this cell as having a planet
				_planet_cells.append(cell)
				
				# Mark proximity cells as excluded
				mark_proximity_cells(cell, proximity, _proximity_excluded_cells)
	
	return planets_placed

# Create a planet spawner and add it to the scene
func create_planet_spawner(cell_coords: Vector2i) -> Node:
	# Initialize cell tracking if needed
	var cell_key = get_cell_key(cell_coords)
	if not _generated_cells.has(cell_key):
		_generated_cells[cell_key] = {
			"planets": [],
			"asteroid_fields": [],
			"stations": []
		}
	
	# Set up the cell seed
	var cell_seed = game_settings.get_seed() + (cell_coords.x * 1000) + (cell_coords.y * 100)
	var seed_offset = cell_seed - game_settings.get_seed()
	
	# Deterministically decide planet type based on cell's seed
	_rng.seed = cell_seed
	var planet_type_roll = _rng.randi_range(0, 100)
	var is_gaseous = planet_type_roll < 20  # 20% chance of gas giant
	
	# Create appropriate planet spawner instance
	var planet_spawner
	
	if is_gaseous:
		# Create a gaseous planet spawner
		if planet_spawner_gaseous_scene:
			planet_spawner = planet_spawner_gaseous_scene.instantiate()
		else:
			planet_spawner = PlanetSpawnerGaseous.new()
			
		# For gas giants, determine type
		var gas_giant_type = _rng.randi_range(0, 3)  # 0-3 are the gas giant types
		
		# Add to scene and configure
		add_child(planet_spawner)
		planet_spawner.gaseous_theme = gas_giant_type + 1  # +1 because 0 is Random
	else:
		# Create a terran planet spawner
		if planet_spawner_terran_scene:
			planet_spawner = planet_spawner_terran_scene.instantiate()
		else:
			planet_spawner = PlanetSpawnerTerran.new()
			
		# For terran planets, determine theme
		var theme_index = _rng.randi_range(0, 6)  # 0-6 are the terran themes
		
		# Add to scene and configure
		add_child(planet_spawner)
		planet_spawner.terran_theme = theme_index + 1  # +1 because 0 is Random
	
	# Configure the spawner using its API
	planet_spawner.set_grid_position(cell_coords.x, cell_coords.y)
	planet_spawner.use_grid_position = true
	planet_spawner.local_seed_offset = seed_offset
	
	# Spawn the planet
	var planet = planet_spawner.spawn_planet()
	
	if not planet:
		push_error("WorldGenerator: Failed to spawn planet at ", cell_coords)
		planet_spawner.queue_free()
		return null
	
	# Connect to planet spawner signals if available
	if planet_spawner.has_signal("planet_spawned"):
		if not planet_spawner.is_connected("planet_spawned", _on_planet_spawned):
			planet_spawner.planet_spawned.connect(_on_planet_spawned)
	
	# Store the spawner
	_planet_spawners[cell_key] = planet_spawner
	
	# Track this planet
	_generated_cells[cell_key].planets.append(planet_spawner)
	_entity_counts.planet += 1
	
	# Emit signal
	entity_generated.emit(planet, "planet", cell_coords)
	
	return planet_spawner

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

# Generate content for a specific cell (except planets)
func generate_cell_content_except_planets(cell_coords: Vector2i) -> void:
	var cell_key = get_cell_key(cell_coords)
	
	# Skip player starting cell
	if cell_coords == game_settings.player_starting_cell:
		return
	
	# Initialize this cell's entity list if needed
	if not _generated_cells.has(cell_key):
		_generated_cells[cell_key] = {
			"planets": [],
			"asteroid_fields": [],
			"stations": []
		}
	
	# Deterministic seeding based on cell coordinates and game seed
	var cell_seed = game_settings.get_seed() + (cell_coords.x * 1000) + (cell_coords.y * 100)
	_rng.seed = cell_seed
	
	# Generate asteroid field if chance hits and we're below max
	var asteroid_roll = _rng.randi_range(1, 100)
	if asteroid_roll <= game_settings.asteroid_field_chance_per_cell and _entity_counts.asteroid_field < game_settings.max_asteroid_fields:
		_spawn_asteroid_field_in_cell(cell_coords, cell_key)
	
	# Generate station if chance hits and we're below max
	var station_roll = _rng.randi_range(1, 100)
	if station_roll <= game_settings.station_chance_per_cell and _entity_counts.station < game_settings.max_stations:
		_spawn_station_in_cell(cell_coords, cell_key)

# Generate content for a specific cell (original method, kept for compatibility)
func generate_cell(cell_coords: Vector2i) -> void:
	if not game_settings:
		push_error("WorldGenerator: Cannot generate cell - GameSettings not found")
		return
	
	# Check if cell is valid
	if not is_valid_cell(cell_coords):
		push_error("WorldGenerator: Cannot generate invalid cell: ", cell_coords)
		return
	
	# Check if cell already generated
	var cell_key = get_cell_key(cell_coords)
	if _generated_cells.has(cell_key):
		if game_settings.debug_mode:
			print("WorldGenerator: Cell already generated: ", cell_coords)
		return
	
	# Initialize this cell's entity list
	_generated_cells[cell_key] = {
		"planets": [],
		"asteroid_fields": [],
		"stations": []
	}
	
	# Check if this cell is excluded due to planet proximity
	if _proximity_excluded_cells.has(cell_key):
		# Don't spawn planets, but other entities are fine
		generate_cell_content_except_planets(cell_coords)
		return
		
	# Always keep the player starting cell clear
	if cell_coords == game_settings.player_starting_cell:
		if game_settings.debug_mode:
			print("WorldGenerator: Keeping player starting cell clear: ", cell_coords)
		return
	
	# Deterministic seeding based on cell coordinates and game seed
	var cell_seed = game_settings.get_seed() + (cell_coords.x * 1000) + (cell_coords.y * 100)
	_rng.seed = cell_seed
	
	# Generate planet if chance hits and we're below max
	var planet_roll = _rng.randi_range(1, 100)
	if planet_roll <= game_settings.planet_chance_per_cell and _entity_counts.planet < game_settings.max_planets:
		# Create a planet spawner for this cell
		var planet_spawner = create_planet_spawner(cell_coords)
		if planet_spawner:
			# Mark this cell as having a planet
			_planet_cells.append(cell_coords)
			
			# Mark proximity cells as excluded
			mark_proximity_cells(cell_coords, game_settings.planet_proximity, _proximity_excluded_cells)
	else:
		# Generate other content
		generate_cell_content_except_planets(cell_coords)
	
	# Debug output
	if game_settings.debug_mode:
		print("WorldGenerator: Generated cell ", cell_coords)

# Spawn an asteroid field in the specified cell
func _spawn_asteroid_field_in_cell(cell_coords: Vector2i, cell_key: String) -> void:
	if asteroid_field_scene == null:
		return
	
	# Create an asteroid field
	var asteroid_field = asteroid_field_scene.instantiate()
	add_child(asteroid_field)
	
	# Position the asteroid field
	var world_pos = game_settings.get_cell_world_position(cell_coords)
	asteroid_field.global_position = world_pos
	
	# Configure the asteroid field if it has the appropriate methods
	if asteroid_field.has_method("generate"):
		# Add some randomization to density and size
		var field_seed = game_settings.get_seed() + (cell_coords.x * 10000) + (cell_coords.y * 1000)
		var density = _rng.randf_range(0.5, 1.5)
		var size = _rng.randf_range(0.7, 1.3)
		
		asteroid_field.generate(field_seed, density, size)
	
	# Track this asteroid field
	_generated_cells[cell_key].asteroid_fields.append(asteroid_field)
	_entity_counts.asteroid_field += 1
	
	# Register with EntityManager if available
	if has_node("/root/EntityManager") and EntityManager.has_method("register_entity"):
		EntityManager.register_entity(asteroid_field, "asteroid_field")
	
	# Emit signal
	entity_generated.emit(asteroid_field, "asteroid_field", cell_coords)

# Spawn a station in the specified cell
func _spawn_station_in_cell(cell_coords: Vector2i, cell_key: String) -> void:
	if station_scene == null:
		return
	
	# Create a station
	var station = station_scene.instantiate()
	add_child(station)
	
	# Position the station
	var world_pos = game_settings.get_cell_world_position(cell_coords)
	station.global_position = world_pos
	
	# Add slight position variation within the cell
	var offset = Vector2(
		_rng.randf_range(-game_settings.grid_cell_size/4.0, game_settings.grid_cell_size/4.0),
		_rng.randf_range(-game_settings.grid_cell_size/4.0, game_settings.grid_cell_size/4.0)
	)
	station.global_position += offset
	
	# Configure the station if it has an initialize method
	if station.has_method("initialize"):
		var station_seed = game_settings.get_seed() + (cell_coords.x * 100000) + (cell_coords.y * 10000)
		station.initialize(station_seed)
	
	# Track this station
	_generated_cells[cell_key].stations.append(station)
	_entity_counts.station += 1
	
	# Register with EntityManager if available
	if has_node("/root/EntityManager") and EntityManager.has_method("register_entity"):
		EntityManager.register_entity(station, "station")
	
	# Emit signal
	entity_generated.emit(station, "station", cell_coords)

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
		"planet": 0,
		"asteroid_field": 0,
		"station": 0
	}
	
	# Reset proximity tracking
	_planet_cells.clear()
	_proximity_excluded_cells.clear()
	_planet_spawners.clear()
	
	# Debug output
	if game_settings and game_settings.debug_mode:
		print("WorldGenerator: World cleared")

# Check if a cell is valid (within grid bounds)
func is_valid_cell(cell_coords: Vector2i) -> bool:
	if not game_settings:
		return false
		
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
	return _generated_cells.has(cell_key)

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

# Regenerate the world with a new seed
func regenerate_with_new_seed(new_seed: int) -> void:
	if game_settings:
		# Update the seed
		game_settings.set_seed(new_seed)
		
		# Regenerate the world
		generate_world()
