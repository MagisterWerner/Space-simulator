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
var planet_spawner_terran_scene: PackedScene
var planet_spawner_gaseous_scene: PackedScene
var asteroid_field_scene: PackedScene
var station_scene: PackedScene

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

# Generate a starter world with exactly one gaseous planet and one lush planet
func generate_starter_world() -> Dictionary:
	# Clear any existing world
	clear_world()
	
	# Emit signal that generation has started
	world_generation_started.emit()
	
	# Initialize RNG with game seed
	if game_settings:
		_rng.seed = game_settings.get_seed()
	else:
		_rng.randomize()
	
	# Reset tracking
	_planet_cells.clear()
	_proximity_excluded_cells.clear()
	_planet_spawners.clear()
	
	# Generate gaseous planet with proximity constraint of 2
	var gaseous_planet_cell = generate_gaseous_planet(2)
	
	# Generate lush planet with proximity constraint of 1
	var lush_planet_cell = generate_lush_planet(1)
	
	# Generate remaining cells (asteroids, stations, etc.)
	if game_settings:
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
				# Skip player starting cell
				if cell == game_settings.player_starting_cell:
					continue
				candidate_cells.append(cell)
	else:
		# Fallback if no game settings
		for x in range(5):
			for y in range(5):
				candidate_cells.append(Vector2i(x, y))
	
	# Shuffle the cells for random distribution
	candidate_cells.shuffle()
	
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
		var cell_seed = 0
		if game_settings:
			cell_seed = game_settings.get_seed() + (cell.x * 1000) + (cell.y * 100)
		else:
			cell_seed = _rng.randi()
		var seed_offset = cell_seed - (game_settings.get_seed() if game_settings else 0)
		
		# Create a planet spawner for this cell
		var planet_spawner = planet_spawner_gaseous_scene.instantiate()
			
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
				# Skip cells that are excluded due to proximity with other planets
				var cell_key = get_cell_key(cell)
				if _proximity_excluded_cells.has(cell_key):
					continue
				# Skip cells that already have content
				if is_cell_generated(cell):
					continue
				candidate_cells.append(cell)
	else:
		# Fallback if no game settings
		for x in range(5):
			for y in range(5):
				var cell = Vector2i(x, y)
				var cell_key = get_cell_key(cell)
				if _proximity_excluded_cells.has(cell_key) or is_cell_generated(cell):
					continue
				candidate_cells.append(cell)
	
	# Shuffle the cells for random distribution
	candidate_cells.shuffle()
	
	# Try to place a lush planet in one of the shuffled cells
	for cell in candidate_cells:
		# Set up the cell seed
		var cell_seed = 0
		if game_settings:
			cell_seed = game_settings.get_seed() + (cell.x * 1000) + (cell.y * 100)
		else:
			cell_seed = _rng.randi()
		var seed_offset = cell_seed - (game_settings.get_seed() if game_settings else 0)
		
		# Create a planet spawner for this cell
		var planet_spawner = planet_spawner_terran_scene.instantiate()
			
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

# Remaining methods...
# (The rest of the file stays the same)

# Generate content for a specific cell (except planets)
func generate_cell_content_except_planets(cell_coords: Vector2i) -> void:
	var cell_key = get_cell_key(cell_coords)
	
	# Skip player starting cell
	if game_settings and cell_coords == game_settings.player_starting_cell:
		return
	
	# Initialize this cell's entity list if needed
	if not _generated_cells.has(cell_key):
		_generated_cells[cell_key] = {
			"planets": [],
			"asteroid_fields": [],
			"stations": []
		}
	
	# Deterministic seeding based on cell coordinates and game seed
	var cell_seed = 0
	if game_settings:
		cell_seed = game_settings.get_seed() + (cell_coords.x * 1000) + (cell_coords.y * 100)
	else:
		cell_seed = _rng.randi()
	_rng.seed = cell_seed
	
	# Generate asteroid field if chance hits and we're below max
	var asteroid_roll = _rng.randi_range(1, 100)
	var asteroid_chance = game_settings.asteroid_field_chance_per_cell if game_settings else 30
	var max_asteroid_fields = game_settings.max_asteroid_fields if game_settings else 10
	
	if asteroid_roll <= asteroid_chance and _entity_counts.asteroid_field < max_asteroid_fields:
		_spawn_asteroid_field_in_cell(cell_coords, cell_key)
	
	# Generate station if chance hits and we're below max
	var station_roll = _rng.randi_range(1, 100)
	var station_chance = game_settings.station_chance_per_cell if game_settings else 20
	var max_stations = game_settings.max_stations if game_settings else 5
	
	if station_roll <= station_chance and _entity_counts.station < max_stations:
		_spawn_station_in_cell(cell_coords, cell_key)

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

# Spawn an asteroid field in the specified cell
func _spawn_asteroid_field_in_cell(cell_coords: Vector2i, cell_key: String) -> void:
	if asteroid_field_scene == null:
		return
	
	# Create an asteroid field
	var asteroid_field = asteroid_field_scene.instantiate()
	add_child(asteroid_field)
	
	# Position the asteroid field
	var world_pos
	if game_settings:
		world_pos = game_settings.get_cell_world_position(cell_coords)
	else:
		world_pos = Vector2(cell_coords.x * 1024, cell_coords.y * 1024)
	asteroid_field.global_position = world_pos
	
	# Configure the asteroid field if it has the appropriate methods
	if asteroid_field.has_method("generate"):
		# Add some randomization to density and size
		var field_seed = 0
		if game_settings:
			field_seed = game_settings.get_seed() + (cell_coords.x * 10000) + (cell_coords.y * 1000)
		else:
			field_seed = _rng.randi()
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
	var world_pos
	if game_settings:
		world_pos = game_settings.get_cell_world_position(cell_coords)
	else:
		world_pos = Vector2(cell_coords.x * 1024, cell_coords.y * 1024)
	station.global_position = world_pos
	
	# Add slight position variation within the cell
	var cell_size = game_settings.grid_cell_size if game_settings else 1024
	var offset = Vector2(
		_rng.randf_range(-cell_size/4.0, cell_size/4.0),
		_rng.randf_range(-cell_size/4.0, cell_size/4.0)
	)
	station.global_position += offset
	
	# Configure the station if it has an initialize method
	if station.has_method("initialize"):
		var station_seed = 0
		if game_settings:
			station_seed = game_settings.get_seed() + (cell_coords.x * 100000) + (cell_coords.y * 10000)
		else:
			station_seed = _rng.randi()
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
