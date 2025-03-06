# autoload/planet_generation_manager.gd
extends Node

signal planet_textures_pregenerated
signal starting_planet_ready(planet, position)
signal planet_generation_complete
signal planet_spawned(planet, cell_coords)
signal planet_generation_progress(current, total)

# Generation settings
@export var pregeneration_batch_size: int = 1  # Generate one at a time for smoothness
@export var target_planet_count: int = 10  # Lower overall count
@export var planet_spawn_probability: float = 0.15  # Slight reduction to 15% of grid cells
@export var min_planet_distance: int = 2  # Minimum cells between planets
@export var generation_timeout: float = 2.0  # Very short timeout per phase
@export var bg_generation_interval: float = 0.1  # Seconds between background generations

# Starting planet configuration
@export var starting_planet_cell: Vector2i = Vector2i(5, 5)  # Default starting location

# Initialization tracking
var initialized: bool = false
var starting_planet_generated: bool = false
var generation_in_progress: bool = false
var current_batch_index: int = 0
var background_generation_timer: Timer
var initialization_timer: Timer
var starting_planet: Node2D = null

# Generated texture pools
var planet_texture_pool: Array = []
var atmosphere_texture_pool: Array = []
var moon_texture_pool: Array = []

# Tracking of placed planets
var placed_planets: Dictionary = {}  # cell_coords (Vector2i) -> planet_node
var occupied_cells: Array = []
var pending_generation_cells: Array = []

# Generation priority tracking
var player_position: Vector2 = Vector2.ZERO
var generation_priority_updated: bool = false

# References to necessary singletons
var _seed_manager = null
var _grid_manager = null
var _entity_manager = null
var _game_manager = null

# Planet scene reference
var planet_scene = null
var moon_scene = null

func _ready() -> void:
	print("PlanetGenerationManager: Initializing...")
	
	# Create timers
	initialization_timer = Timer.new()
	initialization_timer.one_shot = true
	initialization_timer.wait_time = generation_timeout
	initialization_timer.timeout.connect(_on_initialization_timeout)
	add_child(initialization_timer)
	
	background_generation_timer = Timer.new()
	background_generation_timer.one_shot = false
	background_generation_timer.wait_time = bg_generation_interval
	background_generation_timer.timeout.connect(_process_background_generation)
	add_child(background_generation_timer)
	
	# Load scene references
	planet_scene = load("res://scenes/world/planet.tscn")
	moon_scene = load("res://scenes/world/moon.tscn")
	
	# Get singleton references
	_seed_manager = get_node_or_null("/root/SeedManager")
	_grid_manager = get_node_or_null("/root/GridManager")
	_entity_manager = get_node_or_null("/root/EntityManager")
	_game_manager = get_node_or_null("/root/GameManager")
	
	# Connect to game start signal
	if _game_manager and _game_manager.has_signal("game_started"):
		if not _game_manager.game_started.is_connected(_on_game_started):
			_game_manager.game_started.connect(_on_game_started)
	
	# Start with just the starting planet
	call_deferred("_generate_starting_planet")

func _process(_delta) -> void:
	# Update player position if possible
	_update_player_position()

func _update_player_position() -> void:
	# Try to find player through EntityManager
	if _entity_manager and _entity_manager.has_method("get_nearest_entity"):
		var player = _entity_manager.get_nearest_entity(Vector2.ZERO, "player")
		if player and player is Node2D:
			# We have the player - update position and set generation priority
			var new_pos = player.global_position
			if player_position.distance_to(new_pos) > 100:  # Only update if moved significantly
				player_position = new_pos
				generation_priority_updated = true

func _generate_starting_planet() -> void:
	if starting_planet_generated:
		return
		
	print("PlanetGenerationManager: Generating starting planet...")
	
	# Generate exactly one planet for the starting position
	initialization_timer.start()
	
	# Generate the starter planet texture before anything else
	var seed_value = _get_seed_for_starting_planet()
	var planet_data = _generate_planet_texture(seed_value)
	planet_texture_pool.append(planet_data)
	
	var atmosphere_data = _generate_atmosphere_texture(seed_value, planet_data.theme)
	atmosphere_texture_pool.append(atmosphere_data)
	
	# Only generate 1 moon texture for the starting planet
	var moon_data = _generate_moon_texture(seed_value + 100)
	moon_texture_pool.append(moon_data)
	
	# Spawn the starter planet
	starting_planet = _spawn_starter_planet()
	
	# Mark as ready to continue
	starting_planet_generated = true
	initialized = true  # Mark as initialized so game can proceed
	
	# Emit signals
	if starting_planet:
		starting_planet_ready.emit(starting_planet, starting_planet.global_position)
	
	planet_textures_pregenerated.emit()
	
	# Start background generation
	background_generation_timer.start()
	
	print("PlanetGenerationManager: Starting planet ready, continuing generation in background")

func _spawn_starter_planet() -> Node2D:
	# Ensure needed references
	if not _grid_manager or not planet_scene:
		push_error("PlanetGenerationManager: Cannot spawn starting planet - missing references")
		return null
	
	# Get world position for starting cell
	var world_position = _grid_manager.cell_to_world(starting_planet_cell)
	
	# Create planet instance
	var planet_instance = planet_scene.instantiate()
	
	# Add to scene tree via EntityManager if possible
	if _entity_manager:
		_entity_manager.add_child(planet_instance)
		if _entity_manager.has_method("register_entity"):
			_entity_manager.register_entity(planet_instance, "planet")
	else:
		get_tree().current_scene.add_child(planet_instance)
	
	# Position the planet
	planet_instance.global_position = world_position
	
	# Use the first generated texture data
	var planet_data = planet_texture_pool[0]
	var seed_value = planet_data.seed
	
	# Configure settings directly on the planet node
	planet_instance.seed_value = seed_value
	planet_instance.grid_x = starting_planet_cell.x
	planet_instance.grid_y = starting_planet_cell.y
	planet_instance.planet_texture = planet_data.texture
	planet_instance.theme_id = planet_data.theme
	
	# Configure atmosphere if available
	if not atmosphere_texture_pool.is_empty():
		var atm_data = atmosphere_texture_pool[0]
		planet_instance.atmosphere_texture = atm_data.texture
		planet_instance.atmosphere_data = atm_data.data
	
	# Track this planet
	placed_planets[starting_planet_cell] = planet_instance
	occupied_cells.append(starting_planet_cell)
	
	# Emit signal
	planet_spawned.emit(planet_instance, starting_planet_cell)
	
	return planet_instance

func _on_initialization_timeout() -> void:
	# If we hit the timeout, still mark as initialized with whatever we've got
	if not initialized:
		print("PlanetGenerationManager: Initialization timed out, continuing with available textures")
		initialized = true
		planet_textures_pregenerated.emit()
		
		if not starting_planet_generated and not planet_texture_pool.is_empty():
			# Try to spawn starting planet if possible
			starting_planet = _spawn_starter_planet()
			starting_planet_generated = true
			
			if starting_planet:
				starting_planet_ready.emit(starting_planet, starting_planet.global_position)
			
			# Start background generation
			background_generation_timer.start()

func _process_background_generation() -> void:
	if generation_in_progress:
		return
		
	generation_in_progress = true
	
	# Generate one batch of planet textures in the background
	if planet_texture_pool.size() < target_planet_count:
		var start_index = planet_texture_pool.size()
		var count = min(pregeneration_batch_size, target_planet_count - start_index)
		
		for i in range(count):
			var seed_value = _get_seed_for_index(start_index + i)
			
			# Generate planet texture
			var planet_data = _generate_planet_texture(seed_value)
			planet_texture_pool.append(planet_data)
			
			# Generate atmosphere texture
			var atmosphere_data = _generate_atmosphere_texture(seed_value, planet_data.theme)
			atmosphere_texture_pool.append(atmosphere_data)
			
			# Generate just one moon texture per planet (for performance)
			var moon_data = _generate_moon_texture(seed_value + 100)
			moon_texture_pool.append(moon_data)
	
	# If we have pending planet placements, handle one
	elif not pending_generation_cells.is_empty():
		var cell_coords = pending_generation_cells.pop_front()
		if can_place_planet_at(cell_coords):
			spawn_planet_at(cell_coords)
			occupied_cells.append(cell_coords)
	
	generation_in_progress = false

func _generate_planet_texture(seed_value: int) -> Dictionary:
	var planet_generator = PlanetGenerator.new()
	var textures = planet_generator.create_planet_texture(seed_value)
	var theme = planet_generator.get_planet_theme(seed_value)
	
	return {
		"texture": textures[0],
		"seed": seed_value,
		"theme": theme
	}

func _generate_atmosphere_texture(seed_value: int, theme: int) -> Dictionary:
	var atmosphere_generator = AtmosphereGenerator.new()
	var atmosphere_data = atmosphere_generator.generate_atmosphere_data(theme, seed_value)
	var atmosphere_texture = atmosphere_generator.generate_atmosphere_texture(
		theme, 
		seed_value,
		atmosphere_data.color,
		atmosphere_data.thickness
	)
	
	return {
		"texture": atmosphere_texture,
		"seed": seed_value,
		"theme": theme,
		"data": atmosphere_data
	}

func _generate_moon_texture(seed_value: int) -> Dictionary:
	var moon_generator = MoonGenerator.new()
	var texture = moon_generator.create_moon_texture(seed_value)
	var size = moon_generator.get_moon_size(seed_value)
	
	return {
		"texture": texture,
		"seed": seed_value,
		"size": size
	}

func _get_seed_for_starting_planet() -> int:
	# Generate a consistent seed for the starting planet
	if _seed_manager:
		return _seed_manager.get_seed() + 42  # Always the same offset
	else:
		return hash("starting_planet") % 1000000

func _get_seed_for_index(index: int) -> int:
	if _seed_manager:
		return _seed_manager.get_seed() + index * 1000
	else:
		return hash("planet" + str(index)) % 1000000

# Called when game starts
func _on_game_started() -> void:
	if initialized and starting_planet_generated:
		# We already have a starting planet, continue to populate the grid
		populate_grid_with_planets()
	else:
		# Wait for initialization to complete
		if not starting_planet_ready.is_connected(populate_grid_with_planets):
			starting_planet_ready.connect(
				func(_planet, _pos): populate_grid_with_planets(),
				CONNECT_ONE_SHOT
			)

# Spawn planets in grid based on rules
func populate_grid_with_planets() -> void:
	if not _grid_manager:
		push_error("PlanetGenerationManager: Cannot populate grid - GridManager not found")
		return
	
	print("PlanetGenerationManager: Planning planet placement...")
	
	# Get grid size
	var grid_size = _grid_manager.grid_size
	
	# Create a list of all possible cell coordinates
	var all_cells = []
	for x in range(grid_size):
		for y in range(grid_size):
			# Skip the starting planet location
			if Vector2i(x, y) == starting_planet_cell:
				continue
				
			all_cells.append(Vector2i(x, y))
	
	# Shuffle cells for random selection
	randomize_array(all_cells)
	
	# Calculate number of planets to spawn (percentage of cells)
	var target_count = int(all_cells.size() * planet_spawn_probability)
	
	# Queue cells for generation
	pending_generation_cells = []
	for i in range(target_count):
		if i < all_cells.size():
			pending_generation_cells.append(all_cells[i])
	
	# Sort by distance to starting planet for priority
	sort_cells_by_distance_to_starting_planet(pending_generation_cells)
	
	print("PlanetGenerationManager: Queued %d planets for generation" % pending_generation_cells.size())

# Sort cells by distance to starting planet
func sort_cells_by_distance_to_starting_planet(cells: Array) -> void:
	if starting_planet == null:
		return
		
	# Sort cells by Manhattan distance to starting cell
	cells.sort_custom(
		func(a, b):
			var dist_a = abs(a.x - starting_planet_cell.x) + abs(a.y - starting_planet_cell.y)
			var dist_b = abs(b.x - starting_planet_cell.x) + abs(b.y - starting_planet_cell.y)
			return dist_a < dist_b
	)

# Check if a planet can be placed at the given coordinates
func can_place_planet_at(cell_coords: Vector2i) -> bool:
	# Check if this cell is already occupied
	if placed_planets.has(cell_coords):
		return false
	
	# Check adjacent cells (including diagonals)
	for x in range(-1, 2):
		for y in range(-1, 2):
			var neighbor = cell_coords + Vector2i(x, y)
			if placed_planets.has(neighbor):
				return false
	
	return true

# Spawn a planet at the specified grid cell
func spawn_planet_at(cell_coords: Vector2i) -> Node2D:
	if not _grid_manager or not planet_scene:
		push_error("PlanetGenerationManager: Cannot spawn planet - prerequisites not met")
		return null
	
	# Get world position from grid coordinates
	var world_position = _grid_manager.cell_to_world(cell_coords)
	
	# Get a random seed from the pool
	var index = randi() % max(1, planet_texture_pool.size())
	var planet_data = planet_texture_pool[index]
	var seed_value = planet_data.seed
	
	# Create the planet
	var planet_instance = planet_scene.instantiate()
	
	# Add to scene tree
	if _entity_manager and _entity_manager.has_method("register_entity"):
		_entity_manager.add_child(planet_instance)
		_entity_manager.register_entity(planet_instance, "planet")
	else:
		get_tree().current_scene.add_child(planet_instance)
	
	# Position the planet
	planet_instance.global_position = world_position
	
	# Configure settings directly on the planet node
	planet_instance.seed_value = seed_value
	planet_instance.grid_x = cell_coords.x
	planet_instance.grid_y = cell_coords.y
	planet_instance.planet_texture = planet_data.texture
	planet_instance.theme_id = planet_data.theme
	
	# Find matching atmosphere data
	for atm_data in atmosphere_texture_pool:
		if atm_data.seed == seed_value:
			planet_instance.atmosphere_texture = atm_data.texture
			planet_instance.atmosphere_data = atm_data.data
			break
	
	# Track this planet
	placed_planets[cell_coords] = planet_instance
	
	# Emit signal
	planet_spawned.emit(planet_instance, cell_coords)
	
	return planet_instance

# Get moon textures for a specific planet seed
func get_moon_textures_for_planet(planet_seed: int, count: int) -> Array:
	var result = []
	
	for i in range(count):
		var moon_seed = planet_seed + i * 100
		
		# Find matching moon texture
		for moon_data in moon_texture_pool:
			if moon_data.seed == moon_seed:
				result.append(moon_data)
				break
	
	return result

# Utility to randomize array
func randomize_array(arr: Array) -> void:
	var size = arr.size()
	for i in range(size - 1, 0, -1):
		var j = randi() % (i + 1)
		var temp = arr[i]
		arr[i] = arr[j]
		arr[j] = temp

# Get a planet at the specified grid coordinates
func get_planet_at(cell_coords: Vector2i) -> Node2D:
	return placed_planets.get(cell_coords)

# Get the nearest planet to a world position
func get_nearest_planet(world_position: Vector2) -> Node2D:
	if not _grid_manager:
		return null
	
	var cell_coords = _grid_manager.world_to_cell(world_position)
	
	# Check the current cell first
	if placed_planets.has(cell_coords):
		return placed_planets[cell_coords]
	
	# Search in expanding rings
	var checked_cells = [cell_coords]
	var queue = [cell_coords]
	
	while not queue.is_empty():
		var current = queue.pop_front()
		
		# Check all 8 neighbors
		for x in range(-1, 2):
			for y in range(-1, 2):
				if x == 0 and y == 0:
					continue
					
				var neighbor = current + Vector2i(x, y)
				
				# Skip if already checked
				if checked_cells.has(neighbor):
					continue
				
				checked_cells.append(neighbor)
				
				# Check if there's a planet here
				if placed_planets.has(neighbor):
					return placed_planets[neighbor]
				
				# Add to queue for next ring
				queue.append(neighbor)
	
	return null

# Get starting planet position
func get_starting_planet_position() -> Vector2:
	if starting_planet and is_instance_valid(starting_planet):
		return starting_planet.global_position
	return Vector2.ZERO
