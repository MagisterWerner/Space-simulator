# autoload/planet_generation_manager.gd
extends Node

signal planet_textures_pregenerated
signal planet_generation_complete
signal planet_spawned(planet, cell_coords)
signal planet_generation_progress(current, total)

# Generation settings - REDUCED FOR PERFORMANCE
@export var pregeneration_batch_size: int = 2  # Reduced batch size
@export var target_planet_count: int = 10  # Fewer planets to generate
@export var planet_spawn_probability: float = 0.2  # 20% of grid cells
@export var min_planet_distance: int = 2  # Minimum cells between planets
@export var generation_timeout: float = 5.0  # Max seconds for generation

# Initialization tracking
var initialized: bool = false
var generation_in_progress: bool = false
var current_batch_index: int = 0
var initialization_timer: Timer

# Generated texture pools
var planet_texture_pool: Array = []
var atmosphere_texture_pool: Array = []
var moon_texture_pool: Array = []

# Tracking of placed planets
var placed_planets: Dictionary = {}  # cell_coords (Vector2i) -> planet_node
var occupied_cells: Array = []

# References to necessary singletons
var _seed_manager = null
var _grid_manager = null
var _entity_manager = null
var _game_manager = null

# Planet scene reference
var planet_scene = null
var moon_scene = null

func _ready() -> void:
	print("PlanetGenerationManager: Starting...")
	
	# Load scene references
	planet_scene = load("res://scenes/world/planet.tscn")
	moon_scene = load("res://scenes/world/moon.tscn")
	
	if not planet_scene or not moon_scene:
		push_error("PlanetGenerationManager: Failed to load planet or moon scenes")
	
	# Get singleton references
	_seed_manager = get_node_or_null("/root/SeedManager")
	_grid_manager = get_node_or_null("/root/GridManager")
	_entity_manager = get_node_or_null("/root/EntityManager")
	_game_manager = get_node_or_null("/root/GameManager")
	
	# Create generation timeout timer
	initialization_timer = Timer.new()
	initialization_timer.one_shot = true
	initialization_timer.wait_time = generation_timeout
	initialization_timer.timeout.connect(_on_initialization_timeout)
	add_child(initialization_timer)
	
	# Connect to game start signal if available
	if _game_manager and _game_manager.has_signal("game_started"):
		if not _game_manager.game_started.is_connected(_on_game_started):
			_game_manager.game_started.connect(_on_game_started)
	
	# Initialize generation - start with a small batch
	call_deferred("_initialize_first_batch")

func _initialize_first_batch() -> void:
	# Generate just one batch of textures to get started, 
	# then finish the rest asynchronously
	initialization_timer.start()
	
	print("PlanetGenerationManager: Generating initial batch of planet textures...")
	
	# Generate a small initial batch
	var initial_count = min(3, target_planet_count)
	_generate_texture_batch(0, initial_count)
	
	# Mark initialized so the game can proceed
	_finalize_initialization()

func _process(delta) -> void:
	# Continue texture generation in the background
	if initialized and current_batch_index * pregeneration_batch_size < target_planet_count and not generation_in_progress:
		generation_in_progress = true
		var start_index = current_batch_index * pregeneration_batch_size
		var count = min(pregeneration_batch_size, target_planet_count - start_index)
		
		# Generate textures
		_generate_texture_batch(start_index, count)
		current_batch_index += 1
		
		# Update progress
		planet_generation_progress.emit(current_batch_index, ceil(target_planet_count / float(pregeneration_batch_size)))
		generation_in_progress = false

func _generate_texture_batch(start_index: int, count: int) -> void:
	for i in range(count):
		var seed_value = _get_seed_for_index(start_index + i)
		
		# Generate planet texture
		var planet_data = _generate_planet_texture(seed_value)
		planet_texture_pool.append(planet_data)
		
		# Generate atmosphere texture
		var atmosphere_data = _generate_atmosphere_texture(seed_value, planet_data.theme)
		atmosphere_texture_pool.append(atmosphere_data)
		
		# Generate moon textures (1-2 per planet)
		var moon_count = 1 + (seed_value % 2)  # Reduced moon count for performance
		for j in range(moon_count):
			var moon_data = _generate_moon_texture(seed_value + j * 100)
			moon_texture_pool.append(moon_data)

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

func _get_seed_for_index(index: int) -> int:
	if _seed_manager:
		return _seed_manager.get_seed() + index * 1000
	else:
		return hash("planet" + str(index)) % 1000000

func _finalize_initialization() -> void:
	# Stop timer since we're done
	initialization_timer.stop()
	
	initialized = true
	print("PlanetGenerationManager: Initialization complete with %d textures. Continuing generation in background." % 
		planet_texture_pool.size())
	
	planet_textures_pregenerated.emit()

func _on_initialization_timeout() -> void:
	# If we hit the timeout, still mark as initialized with whatever we've got
	if not initialized:
		print("PlanetGenerationManager: Initialization timed out, continuing with available textures")
		initialized = true
		planet_textures_pregenerated.emit()

# Called when game starts
func _on_game_started() -> void:
	print("PlanetGenerationManager: Game started, populating planets...")
	
	if initialized:
		populate_grid_with_planets()
	else:
		# Wait for initialization to complete
		if not planet_textures_pregenerated.is_connected(populate_grid_with_planets):
			planet_textures_pregenerated.connect(populate_grid_with_planets, CONNECT_ONE_SHOT)

# Spawn planets in grid based on rules
func populate_grid_with_planets() -> void:
	if not _grid_manager:
		push_error("PlanetGenerationManager: Cannot populate grid - GridManager not found")
		return
	
	print("PlanetGenerationManager: Starting planet spawning...")
	
	# Get grid size
	var grid_size = _grid_manager.grid_size
	
	# Create a list of all possible cell coordinates
	var all_cells = []
	for x in range(grid_size):
		for y in range(grid_size):
			all_cells.append(Vector2i(x, y))
	
	# Shuffle cells for random selection
	randomize_array(all_cells)
	
	# Calculate number of planets to spawn (20% of cells)
	var target_count = int(all_cells.size() * planet_spawn_probability)
	var spawned_count = 0
	
	# Try to place planets
	for cell_coords in all_cells:
		if spawned_count >= target_count:
			break
		
		if can_place_planet_at(cell_coords):
			spawn_planet_at(cell_coords)
			spawned_count += 1
			occupied_cells.append(cell_coords)
	
	print("PlanetGenerationManager: Spawned %d planets" % spawned_count)
	planet_generation_complete.emit()

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
