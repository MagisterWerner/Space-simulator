# autoload/world_generator.gd
extends Node

signal world_structure_generated
signal cell_activated(cell_coords)
signal cell_deactivated(cell_coords)

# Planet type enum referenced from PlanetGenerator
enum PlanetType {
	TERRAN,   # Rocky/solid surface planets (Earth-like, desert, ice, etc.)
	GASEOUS   # Gas planets without solid surface (gas giants, etc.)
}

# Specific planet themes within categories
enum PlanetTheme {
	# Terran planets
	ARID,
	ICE,
	LAVA,
	LUSH,
	DESERT,
	ALPINE,
	OCEAN,
	
	# Gaseous planets
	GAS_GIANT  # Currently the only gaseous type
}

# World configuration
@export var active_radius: int = 2  # How many cells around player to keep active
@export var terran_planets_count: int = 10  # Total number of terran planets to generate
@export var min_terran_distance: int = 1  # Min distance between terran planets
@export var gas_giant_buffer: int = 2  # How far terran planets must be from gas giant
@export var asteroid_field_chance: float = 0.3
@export var station_chance: float = 0.1

# World state tracking
var _world_cells: Dictionary = {}  # Stores what's in each cell
var _active_cells: Array[Vector2i] = []  # Currently active cells
var _generated: bool = false
var _player_cell: Vector2i = Vector2i(-1, -1)
var _player_start_cell: Vector2i = Vector2i(-1, -1)
var _gas_giant_cell: Vector2i = Vector2i(-1, -1)

func _ready() -> void:
	# Connect to the player cell changed signal in GridManager
	if has_node("/root/GridManager"):
		GridManager.player_cell_changed.connect(_on_player_cell_changed)
	
	# Initialize on game start with a delayed call to ensure all autoloads are ready
	call_deferred("generate_world_structure")

# Get the grid size from available sources
func _get_grid_size() -> int:
	# Try to get grid size from GridManager
	if has_node("/root/GridManager"):
		return GridManager.grid_size
	
	# Try to get from WorldGrid node if it exists
	var world_grid = get_node_or_null("/root/Main/WorldGrid")
	if world_grid and world_grid.has_method("get_grid_size"):
		return world_grid.grid_size
	elif world_grid and "grid_size" in world_grid:
		return world_grid.grid_size
	
	# Default fallback value
	return 10

# Main function to generate the entire world structure
func generate_world_structure() -> void:
	if _generated:
		return
	
	# Get the global seed for deterministic generation
	var global_seed = SeedManager.get_seed()
	var rng = RandomNumberGenerator.new()
	rng.seed = global_seed
	
	# Get grid size from available sources
	var grid_size = _get_grid_size()
	
	print("Generating world with grid size: ", grid_size)
	
	# Initialize all cells as empty
	for x in range(grid_size):
		for y in range(grid_size):
			var cell_coords = Vector2i(x, y)
			_world_cells[cell_coords] = {
				"seed": global_seed + (x * 1000) + (y * 100),
				"generated": false,
				"contents": [],
				"has_planet": false,
				"has_asteroid_field": false,
				"has_station": false,
				"planet_type": -1,  # -1 means no planet
				"planet_theme": -1  # -1 means no theme
			}
	
	# Step 1: Place ONE gas giant in a random cell
	_gas_giant_cell = Vector2i(
		rng.randi_range(gas_giant_buffer, grid_size - gas_giant_buffer - 1),
		rng.randi_range(gas_giant_buffer, grid_size - gas_giant_buffer - 1)
	)
	
	var gas_giant_data = _world_cells[_gas_giant_cell]
	gas_giant_data.has_planet = true
	gas_giant_data.planet_type = PlanetType.GASEOUS
	gas_giant_data.planet_theme = PlanetTheme.GAS_GIANT
	
	# Add gas giant to contents
	gas_giant_data.contents.append({
		"type": "planet",
		"planet_type": PlanetType.GASEOUS,
		"terran_theme": -1,  # Not applicable for gas giants
		"position_offset": Vector2(0, 0),  # Center of cell
		"local_seed_offset": 42,  # Fixed seed offset for reproducibility
		"entity": null  # Will hold the actual entity instance when spawned
	})
	
	print("Placed gas giant at: ", _gas_giant_cell)
	
	# Step 2: Place ONE OF EACH terran planet type in separate cells
	var terran_themes_to_place = [
		PlanetTheme.ARID,
		PlanetTheme.ICE,
		PlanetTheme.LAVA,
		PlanetTheme.LUSH,
		PlanetTheme.DESERT,
		PlanetTheme.ALPINE,
		PlanetTheme.OCEAN
	]
	
	var placed_terran_planets = []
	var lush_planet_cell = null
	
	# First place one of each terran planet type
	for theme in terran_themes_to_place:
		var available_cells = _find_valid_planet_cells(placed_terran_planets, grid_size)
		if available_cells.is_empty():
			push_warning("No more available cells for terran planet theme: " + str(theme))
			break
		
		# Choose a random available cell
		var cell_idx = rng.randi_range(0, available_cells.size() - 1)
		var planet_cell = available_cells[cell_idx]
		
		# Place the terran planet
		_place_terran_planet(planet_cell, theme, rng)
		placed_terran_planets.append(planet_cell)
		
		if theme == PlanetTheme.LUSH:
			lush_planet_cell = planet_cell
			_player_start_cell = planet_cell  # Set player to spawn at LUSH planet
	
	print("Placed one of each terran planet type. Total placed: ", placed_terran_planets.size())
	
	# Step 3: Fill remaining slots with random terran planets
	while placed_terran_planets.size() < terran_planets_count:
		var available_cells = _find_valid_planet_cells(placed_terran_planets, grid_size)
		if available_cells.is_empty():
			print("No more available cells for additional terran planets")
			break
		
		# Choose a random available cell
		var cell_idx = rng.randi_range(0, available_cells.size() - 1)
		var planet_cell = available_cells[cell_idx]
		
		# Choose a random terran theme
		var random_theme = terran_themes_to_place[rng.randi_range(0, terran_themes_to_place.size() - 1)]
		
		# Place the terran planet
		_place_terran_planet(planet_cell, random_theme, rng)
		placed_terran_planets.append(planet_cell)
		
		# If we still don't have a LUSH planet (unlikely but possible), check if this is one
		if lush_planet_cell == null and random_theme == PlanetTheme.LUSH:
			lush_planet_cell = planet_cell
			_player_start_cell = planet_cell
	
	print("Added additional random terran planets. Total planets: ", placed_terran_planets.size() + 1)  # +1 for gas giant
	
	# Step 4: Add asteroid fields and stations in remaining cells
	for cell_coords in _world_cells.keys():
		var cell_data = _world_cells[cell_coords]
		
		# Skip cells that already have planets
		if cell_data.has_planet:
			continue
		
		# Random chance for asteroid field
		if rng.randf() < asteroid_field_chance:
			cell_data.has_asteroid_field = true
			
			# Generate asteroid field parameters
			var asteroid_count = rng.randi_range(5, 15)
			var field_radius = rng.randf_range(0.2, 0.4)  # As percentage of cell size
			var field_position = Vector2(
				rng.randf_range(-0.3, 0.3),
				rng.randf_range(-0.3, 0.3)
			)
			
			cell_data.contents.append({
				"type": "asteroid_field",
				"count": asteroid_count,
				"radius": field_radius,
				"position_offset": field_position,
				"asteroids": []  # Will hold asteroid entities
			})
		
		# Random chance for station (but not in cells with asteroid fields)
		elif rng.randf() < station_chance:
			cell_data.has_station = true
			
			# Station position
			var station_position = Vector2(
				rng.randf_range(-0.3, 0.3),
				rng.randf_range(-0.3, 0.3)
			)
			
			# Station type
			var station_type = rng.randi() % 3  # 0-2 different station types
			
			cell_data.contents.append({
				"type": "station",
				"station_type": station_type,
				"position_offset": station_position,
				"entity": null
			})
	
	# Mark world generation as complete
	_generated = true
	world_structure_generated.emit()
	print("World structure generated successfully with seed: ", global_seed)
	
	# If player is already in a cell, activate cells around them
	# Otherwise, set player position to a LUSH planet
	if _player_cell.x >= 0:
		_update_active_cells()
	else:
		# Move player to the LUSH planet for starting position
		_player_cell = _player_start_cell
		
		# If we have a GameManager, position the player at the LUSH planet
		if has_node("/root/GameManager") and is_instance_valid(GameManager.player_ship):
			var cell_pos = GridManager.cell_to_world(_player_start_cell)
			GameManager.player_ship.global_position = cell_pos
			print("Positioned player at LUSH planet: ", _player_start_cell)
		
		_update_active_cells()

# Helper to place a terran planet in a specific cell
func _place_terran_planet(cell_coords: Vector2i, theme: int, rng: RandomNumberGenerator) -> void:
	var cell_data = _world_cells[cell_coords]
	
	# Mark cell as having a planet
	cell_data.has_planet = true
	cell_data.planet_type = PlanetType.TERRAN
	cell_data.planet_theme = theme
	
	# Slightly randomize position within cell
	var position_offset = Vector2(
		rng.randf_range(-0.15, 0.15),
		rng.randf_range(-0.15, 0.15)
	)
	
	# Add planet to contents
	cell_data.contents.append({
		"type": "planet",
		"planet_type": PlanetType.TERRAN,
		"terran_theme": theme,
		"position_offset": position_offset,
		"local_seed_offset": theme * 100 + rng.randi_range(1, 99),  # Theme-based seed offset
		"entity": null  # Will hold the actual entity instance when spawned
	})
	
	print("Placed terran planet with theme ", theme, " at cell: ", cell_coords)

# Find valid cells for placing a terran planet
func _find_valid_planet_cells(existing_planets: Array, grid_size: int) -> Array:
	var valid_cells = []
	
	for x in range(grid_size):
		for y in range(grid_size):
			var cell_coords = Vector2i(x, y)
			
			# Skip cells that already have planets
			if _world_cells[cell_coords].has_planet:
				continue
			
			# Check if too close to gas giant
			if _gas_giant_cell.x >= 0 and _is_too_close_to_gas_giant(cell_coords):
				continue
			
			# Check if too close to other terran planets
			var too_close = false
			for planet_cell in existing_planets:
				if _is_too_close_to_terran(cell_coords, planet_cell):
					too_close = true
					break
			
			if too_close:
				continue
			
			# If we made it here, the cell is valid
			valid_cells.append(cell_coords)
	
	return valid_cells

# Check if a cell is too close to the gas giant
func _is_too_close_to_gas_giant(cell_coords: Vector2i) -> bool:
	if _gas_giant_cell.x < 0:  # No gas giant placed yet
		return false
	
	# Calculate Manhattan distance
	var distance = abs(cell_coords.x - _gas_giant_cell.x) + abs(cell_coords.y - _gas_giant_cell.y)
	return distance <= gas_giant_buffer

# Check if a cell is too close to another terran planet
func _is_too_close_to_terran(cell_coords: Vector2i, terran_cell: Vector2i) -> bool:
	# Calculate Manhattan distance
	var distance = abs(cell_coords.x - terran_cell.x) + abs(cell_coords.y - terran_cell.y)
	return distance <= min_terran_distance

# Activate a cell (spawn its contents)
func activate_cell(cell_coords: Vector2i) -> void:
	if not _world_cells.has(cell_coords):
		push_error("WorldGenerator: Cannot activate cell that hasn't been generated: ", cell_coords)
		return
	
	var cell_data = _world_cells[cell_coords]
	if cell_data.generated:
		return  # Already generated
	
	# Get the world position of this cell
	var cell_position = GridManager.cell_to_world(cell_coords)
	
	# Spawn all contents
	for content in cell_data.contents:
		match content.type:
			"planet":
				_spawn_planet(cell_coords, content, cell_position)
			"asteroid_field":
				_spawn_asteroid_field(cell_coords, content, cell_position)
			"station":
				_spawn_station(cell_coords, content, cell_position)
	
	cell_data.generated = true
	cell_activated.emit(cell_coords)
	print("Activated cell: ", cell_coords)

# Deactivate a cell (despawn its contents)
func deactivate_cell(cell_coords: Vector2i) -> void:
	if not _world_cells.has(cell_coords) or not _world_cells[cell_coords].generated:
		return
	
	var cell_data = _world_cells[cell_coords]
	
	# Clean up all spawned entities
	for content in cell_data.contents:
		match content.type:
			"planet":
				if content.entity and is_instance_valid(content.entity):
					content.entity.queue_free()
					content.entity = null
			"asteroid_field":
				for asteroid in content.asteroids:
					if is_instance_valid(asteroid):
						asteroid.queue_free()
				content.asteroids.clear()
			"station":
				if content.entity and is_instance_valid(content.entity):
					content.entity.queue_free()
					content.entity = null
	
	cell_data.generated = false
	cell_deactivated.emit(cell_coords)
	print("Deactivated cell: ", cell_coords)

# Helper to spawn a planet
func _spawn_planet(cell_coords: Vector2i, planet_data: Dictionary, cell_position: Vector2) -> void:
	# Create a planet spawner
	var planet_spawner_scene = load("res://scenes/world/planet_spawner.tscn")
	if not planet_spawner_scene:
		push_error("WorldGenerator: Failed to load planet_spawner.tscn")
		return
		
	var planet_spawner = planet_spawner_scene.instantiate()
	var game_scene = get_tree().current_scene
	game_scene.add_child(planet_spawner)
	
	# Calculate position with offset
	var position = cell_position + (planet_data.position_offset * GridManager.cell_size)
	planet_spawner.global_position = position
	
	# Configure the spawner with the right parameters
	planet_spawner.planet_category = planet_data.planet_type
	planet_spawner.terran_theme = planet_data.terran_theme
	planet_spawner.grid_x = cell_coords.x
	planet_spawner.grid_y = cell_coords.y
	planet_spawner.local_seed_offset = planet_data.local_seed_offset
	
	# Set planet scale based on type
	if planet_data.planet_type == PlanetType.GASEOUS:
		planet_spawner.planet_scale = 1.5  # Gas giants are larger
	else:
		planet_spawner.planet_scale = 1.0
	
	# Auto-spawn the planet
	planet_spawner.auto_spawn = true
	
	# Store reference to the spawner
	planet_data.entity = planet_spawner
	
	if cell_coords == _player_start_cell:
		print("Spawned LUSH planet at player start location: ", cell_coords)

# Helper to spawn asteroid field
func _spawn_asteroid_field(cell_coords: Vector2i, field_data: Dictionary, cell_position: Vector2) -> void:
	# Calculate center position for the asteroid field
	var center_position = cell_position + (field_data.position_offset * GridManager.cell_size)
	var asteroid_count = field_data.count
	var field_radius = field_data.radius * GridManager.cell_size
	
	# Get a reference to the current scene
	var game_scene = get_tree().current_scene
	
	# Create RNG for asteroid placement
	var rng = RandomNumberGenerator.new()
	rng.seed = _world_cells[cell_coords].seed + 789  # Use a different offset for asteroids
	
	# Spawn the asteroids
	for i in range(asteroid_count):
		# Random position within the field radius (using polar coordinates for better distribution)
		var angle = rng.randf() * TAU  # Random angle
		var distance = rng.randf() * field_radius  # Random distance within field
		var position = center_position + Vector2(cos(angle), sin(angle)) * distance
		
		# Random asteroid size category: small, medium, large
		var size_category = rng.randi() % 3
		var size_name = "small"
		match size_category:
			0: size_name = "small"
			1: size_name = "medium"
			2: size_name = "large"
		
		# Random rotation
		var rotation = rng.randf() * TAU
		var rotation_speed = rng.randf_range(-0.5, 0.5)
		
		# Try to load and instantiate asteroid scene
		var asteroid
		if ResourceLoader.exists("res://scenes/asteroid.tscn"):
			asteroid = load("res://scenes/asteroid.tscn").instantiate()
		else:
			# Fallback to creating a basic asteroid node if scene doesn't exist
			asteroid = Node2D.new()
			asteroid.name = "Asteroid"
		
		# Configure the asteroid
		asteroid.global_position = position
		asteroid.rotation = rotation
		
		# Apply size and other properties if it has proper methods
		if asteroid.has_method("setup"):
			asteroid.setup(size_name, rng.randi() % 3, 1.0, rotation_speed)
		
		# Add to scene
		game_scene.add_child(asteroid)
		
		# Register with EntityManager if available
		if has_node("/root/EntityManager"):
			EntityManager.register_entity(asteroid, "asteroid")
		
		# Add to the list of spawned asteroids in this field
		field_data.asteroids.append(asteroid)

# Helper to spawn station
func _spawn_station(cell_coords: Vector2i, station_data: Dictionary, cell_position: Vector2) -> void:
	# Calculate position for the station
	var station_position = cell_position + (station_data.position_offset * GridManager.cell_size)
	
	# Get a reference to the current scene
	var game_scene = get_tree().current_scene
	
	# Determine station scene based on type
	var station_scene_path = "res://scenes/stations/station_" + str(station_data.station_type) + ".tscn"
	
	# Fallback to a generic station if specific one doesn't exist
	if not ResourceLoader.exists(station_scene_path):
		station_scene_path = "res://scenes/stations/station.tscn"
	
	# Try to load and instantiate the station
	var station
	if ResourceLoader.exists(station_scene_path):
		station = load(station_scene_path).instantiate()
	else:
		# Fallback to creating a basic station node if scene doesn't exist
		station = Node2D.new()
		station.name = "Station_" + str(station_data.station_type)
	
	# Configure the station
	station.global_position = station_position
	
	# Initialize station with data if it has an initialize method
	if station.has_method("initialize"):
		var station_seed = _world_cells[cell_coords].seed + 456 + station_data.station_type
		station.initialize({
			"seed": station_seed,
			"type": station_data.station_type,
			"grid_x": cell_coords.x, 
			"grid_y": cell_coords.y
		})
	
	# Add to scene
	game_scene.add_child(station)
	
	# Register with EntityManager if available
	if has_node("/root/EntityManager"):
		EntityManager.register_entity(station, "station")
	
	# Store reference to the station
	station_data.entity = station

# Called when player moves to a new cell
func _on_player_cell_changed(_old_cell: Vector2i, new_cell: Vector2i) -> void:
	_player_cell = new_cell
	_update_active_cells()

# Update which cells should be active based on player position
func _update_active_cells() -> void:
	var new_active_cells: Array[Vector2i] = []
	
	# Get grid size from available sources
	var grid_size = _get_grid_size()
	
	# Calculate which cells should be active (within active_radius of player)
	for x in range(_player_cell.x - active_radius, _player_cell.x + active_radius + 1):
		for y in range(_player_cell.y - active_radius, _player_cell.y + active_radius + 1):
			var cell = Vector2i(x, y)
			
			# Skip invalid cells
			if x < 0 or y < 0 or x >= grid_size or y >= grid_size:
				continue
				
			new_active_cells.append(cell)
	
	# Activate cells that weren't active before
	for cell in new_active_cells:
		if not _active_cells.has(cell):
			activate_cell(cell)
	
	# Deactivate cells that are no longer active
	for cell in _active_cells:
		if not new_active_cells.has(cell):
			deactivate_cell(cell)
	
	_active_cells = new_active_cells
