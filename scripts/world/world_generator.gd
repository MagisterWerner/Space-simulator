# scripts/world/world_generator.gd
# ========================
# Purpose:
#   Procedurally generates the game world based on GameSettings
#   Handles spawning of planets, asteroids, and stations
#   Maintains consistent generation based on the game seed
#
# Interface:
#   Signals:
#     - world_generation_started
#     - world_generation_completed
#     - entity_generated(entity, type, cell)
#
#   Methods:
#     - generate_world(): Generate the entire world
#     - generate_cell(cell_coords): Generate content for a specific cell
#     - clear_world(): Clear all generated entities
#     - is_cell_generated(cell_coords): Check if a cell has been generated
#
# Dependencies:
#   - GameSettings
#   - PlanetSpawner
#   - EntityManager (optional)

extends Node
class_name WorldGenerator

signal world_generation_started
signal world_generation_completed
signal entity_generated(entity, type, cell)

# References to required components
var game_settings: GameSettings = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Scene references
@export var planet_spawner_scene: PackedScene
@export var asteroid_field_scene: PackedScene
@export var station_scene: PackedScene

# Generation tracking
var _generated_cells: Dictionary = {}  # cell_coords (string) -> { planets: [], asteroids: [], stations: [] }
var _entity_counts: Dictionary = {
	"planet": 0,
	"asteroid_field": 0,
	"station": 0
}

# Initialization
func _ready() -> void:
	# Find GameSettings in the main scene
	var main_scene = get_tree().current_scene
	game_settings = main_scene.get_node_or_null("GameSettings")
	
	# Load required scenes if not set
	if planet_spawner_scene == null:
		planet_spawner_scene = load("res://scenes/world/planet_spawner.tscn")
	
	if asteroid_field_scene == null:
		var asteroid_path = "res://scenes/world/asteroid_field.tscn"
		if ResourceLoader.exists(asteroid_path):
			asteroid_field_scene = load(asteroid_path)
	
	if station_scene == null:
		var station_path = "res://scenes/world/station.tscn"
		if ResourceLoader.exists(station_path):
			station_scene = load(station_path)
	
	# Debug output
	if game_settings and game_settings.debug_mode:
		print("WorldGenerator: Initialized with game seed ", game_settings.get_seed())

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
	
	# Generate each cell in the grid
	for x in range(game_settings.grid_size):
		for y in range(game_settings.grid_size):
			var cell = Vector2i(x, y)
			generate_cell(cell)
	
	# Emit signal that generation is complete
	world_generation_completed.emit()
	
	# Debug output
	if game_settings.debug_mode:
		print("WorldGenerator: World generation complete")
		print("- Planets: ", _entity_counts.planet)
		print("- Asteroid Fields: ", _entity_counts.asteroid_field)
		print("- Stations: ", _entity_counts.station)

# Generate content for a specific cell
func generate_cell(cell_coords: Vector2i) -> void:
	if not game_settings:
		push_error("WorldGenerator: Cannot generate cell - GameSettings not found")
		return
	
	# Check if cell is valid
	if not game_settings.is_valid_cell(cell_coords):
		push_error("WorldGenerator: Cannot generate invalid cell: ", cell_coords)
		return
	
	# Check if cell already generated
	var cell_key = str(cell_coords.x) + "," + str(cell_coords.y)
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
	
	# Deterministic seeding based on cell coordinates and game seed
	var cell_seed = game_settings.get_seed() + (cell_coords.x * 1000) + (cell_coords.y * 100)
	_rng.seed = cell_seed
	
	# Determine what to spawn in this cell based on probabilities
	_generate_cell_content(cell_coords, cell_key)
	
	# Debug output
	if game_settings.debug_mode:
		print("WorldGenerator: Generated cell ", cell_coords)

# Internal method to generate cell content
func _generate_cell_content(cell_coords: Vector2i, cell_key: String) -> void:
	# Always keep the player starting cell clear
	if cell_coords == game_settings.player_starting_cell:
		if game_settings.debug_mode:
			print("WorldGenerator: Keeping player starting cell clear: ", cell_coords)
		return
	
	# Generate planet if chance hits and we're below max
	var planet_roll = _rng.randi_range(1, 100)
	if planet_roll <= game_settings.planet_chance_per_cell and _entity_counts.planet < game_settings.max_planets:
		_spawn_planet_in_cell(cell_coords, cell_key)
	
	# Generate asteroid field if chance hits and we're below max
	var asteroid_roll = _rng.randi_range(1, 100)
	if asteroid_roll <= game_settings.asteroid_field_chance_per_cell and _entity_counts.asteroid_field < game_settings.max_asteroid_fields:
		_spawn_asteroid_field_in_cell(cell_coords, cell_key)
	
	# Generate station if chance hits and we're below max
	var station_roll = _rng.randi_range(1, 100)
	if station_roll <= game_settings.station_chance_per_cell and _entity_counts.station < game_settings.max_stations:
		_spawn_station_in_cell(cell_coords, cell_key)

# Spawn a planet in the specified cell
func _spawn_planet_in_cell(cell_coords: Vector2i, cell_key: String) -> void:
	if planet_spawner_scene == null:
		return
	
	# Create a planet spawner
	var planet_spawner = planet_spawner_scene.instantiate()
	add_child(planet_spawner)
	
	# Configure the spawner
	planet_spawner.grid_x = cell_coords.x
	planet_spawner.grid_y = cell_coords.y
	planet_spawner.use_grid_position = true
	
	# Deterministically decide planet type
	var planet_type_roll = _rng.randi_range(0, 100)
	var is_gaseous = planet_type_roll < 20  # 20% chance of gas giant
	
	# For terran planets, determine theme
	var theme_index = -1
	if not is_gaseous:
		theme_index = _rng.randi_range(0, 6)  # 0-6 are the terran themes
	
	# Set the planet type
	planet_spawner.force_planet_type(is_gaseous, theme_index)
	
	# Spawn the planet
	var planet = planet_spawner.spawn_planet()
	
	# Track this planet
	_generated_cells[cell_key].planets.append(planet_spawner)
	_entity_counts.planet += 1
	
	# Emit signal
	entity_generated.emit(planet, "planet", cell_coords)

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
	# Fixed the integer division issue by using 4.0 instead of 4
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
	if has_node("/root/EntityManager"):
		EntityManager.register_entity(station, "station")
	
	# Emit signal
	entity_generated.emit(station, "station", cell_coords)

# Clear all generated world content
func clear_world() -> void:
	# Clean up all generated entities
	for cell_key in _generated_cells:
		var cell_data = _generated_cells[cell_key]
		
		# Clear planets
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
				if has_node("/root/EntityManager"):
					EntityManager.deregister_entity(station)
				station.queue_free()
	
	# Reset tracking
	_generated_cells.clear()
	_entity_counts = {
		"planet": 0,
		"asteroid_field": 0,
		"station": 0
	}
	
	# Debug output
	if game_settings and game_settings.debug_mode:
		print("WorldGenerator: World cleared")

# Check if a cell has been generated
func is_cell_generated(cell_coords: Vector2i) -> bool:
	var cell_key = str(cell_coords.x) + "," + str(cell_coords.y)
	return _generated_cells.has(cell_key)

# Get all generated entities in a cell
func get_cell_entities(cell_coords: Vector2i) -> Array:
	var cell_key = str(cell_coords.x) + "," + str(cell_coords.y)
	var result = []
	
	if not _generated_cells.has(cell_key):
		return result
	
	var cell_data = _generated_cells[cell_key]
	
	# Add planets (actually planet spawners)
	for planet_spawner in cell_data.planets:
		if is_instance_valid(planet_spawner):
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
