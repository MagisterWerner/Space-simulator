# scripts/world/world_generator.gd
# A utility class that integrates the grid and planet systems
# to enable procedural world generation
extends Node
class_name WorldGenerator

signal world_generation_started
signal world_generation_completed
signal cell_generated(coords, content_type)
signal dependencies_found

@export_category("World Configuration")
@export var default_cell_size: int = 1024
@export var default_grid_size: int = 5
@export var use_deterministic_seed: bool = true

@export_category("Planet Configuration")
@export var planet_density: float = 0.4  # 0.0 to 1.0, fraction of cells with planets
@export var terran_probability: float = 0.7  # 0.0 to 1.0, probability of terran vs gaseous

@export_category("Debug")
@export var debug_mode: bool = false

# References to required nodes
var _grid: WorldGrid = null
var _planet_spawner: PlanetSpawner = null

# Current generation state
var _generation_in_progress: bool = false
var _current_seed: int = 0
var _generated_planets: Array = []
var _dependencies_initialized: bool = false
var _dependency_attempts: int = 0
var _max_dependency_attempts: int = 10

# Connection tracking
var _connected_signals: Array = []

func _ready() -> void:
	# Find grid and planet spawner after a frame to ensure the scene tree is ready
	call_deferred("_find_dependencies")

func _exit_tree() -> void:
	# Clean up all connections when being removed
	for signal_data in _connected_signals:
		if signal_data.source.has_signal(signal_data.signal_name) and signal_data.source.is_connected(signal_data.signal_name, signal_data.callable):
			signal_data.source.disconnect(signal_data.signal_name, signal_data.callable)
	_connected_signals.clear()

func _find_dependencies() -> void:
	"""Find required dependencies for world generation using multiple methods"""
	# Don't try indefinitely
	if _dependency_attempts >= _max_dependency_attempts:
		push_error("WorldGenerator: Failed to find dependencies after multiple attempts.")
		return
	
	_dependency_attempts += 1
	
	# Wait for the scene tree to be ready
	await get_tree().process_frame
	
	var found_grid = false
	var found_spawner = false
	
	# Method 1: Look for WorldGrid in groups
	if not found_grid:
		var grids = get_tree().get_nodes_in_group("world_grid")
		if not grids.is_empty():
			var potential_grid = grids[0]
			if is_instance_valid(potential_grid) and potential_grid is WorldGrid:
				_grid = potential_grid
				found_grid = true
				if debug_mode:
					print("WorldGenerator: Found grid in 'world_grid' group: ", _grid.get_path())
	
	# Method 2: Look for WorldGrid in main scene
	if not found_grid:
		var main = get_tree().current_scene
		if main:
			var grid = main.get_node_or_null("WorldGrid")
			if is_instance_valid(grid) and grid is WorldGrid:
				_grid = grid
				found_grid = true
				if debug_mode:
					print("WorldGenerator: Found grid in main scene: ", _grid.get_path())
	
	# Method 3: Try to find grid in global scene tree
	if not found_grid:
		var nodes = get_tree().get_nodes_in_group("world_grid")
		for node in nodes:
			if is_instance_valid(node) and node is WorldGrid:
				_grid = node
				found_grid = true
				if debug_mode:
					print("WorldGenerator: Found grid in scene tree: ", _grid.get_path())
				break
	
	# Method 4: Look for grid relative to this node
	if not found_grid:
		var root = get_tree().root
		var grid = root.get_node_or_null("Main/WorldGrid")
		if is_instance_valid(grid) and grid is WorldGrid:
			_grid = grid
			found_grid = true
			if debug_mode:
				print("WorldGenerator: Found grid at absolute path: ", _grid.get_path())
	
	# Method 5: Create a new grid if still not found
	if not found_grid:
		if debug_mode:
			print("WorldGenerator: Could not find existing grid, creating a new one.")
		
		_grid = WorldGrid.new()
		_grid.cell_size = default_cell_size
		_grid.grid_size = default_grid_size
		_grid.name = "WorldGrid"
		add_child(_grid)
		found_grid = true
	
	# Now look for PlanetSpawner with similar methods
	
	# Method 1: Look for PlanetSpawner in groups
	if not found_spawner:
		var spawners = get_tree().get_nodes_in_group("planet_spawner")
		if not spawners.is_empty():
			var potential_spawner = spawners[0]
			if is_instance_valid(potential_spawner) and potential_spawner is PlanetSpawner:
				_planet_spawner = potential_spawner
				found_spawner = true
				if debug_mode:
					print("WorldGenerator: Found planet spawner in 'planet_spawner' group: ", _planet_spawner.get_path())
	
	# Method 2: Look for PlanetSpawner in scene
	if not found_spawner:
		var main = get_tree().current_scene
		if main:
			var spawner = main.get_node_or_null("PlanetSpawner")
			if is_instance_valid(spawner) and spawner is PlanetSpawner:
				_planet_spawner = spawner
				found_spawner = true
				if debug_mode:
					print("WorldGenerator: Found planet spawner in main scene: ", _planet_spawner.get_path())
	
	# Method 3: Create a new spawner if still not found
	if not found_spawner:
		if debug_mode:
			print("WorldGenerator: Could not find existing planet spawner, creating a new one.")
		
		_planet_spawner = PlanetSpawner.new()
		_planet_spawner.name = "PlanetSpawner"
		add_child(_planet_spawner)
		found_spawner = true
	
	# Ensure we have both dependencies before proceeding
	if is_instance_valid(_grid) and is_instance_valid(_planet_spawner):
		# Connect to grid signals for cell content management
		if _grid.has_signal("cell_content_cleared"):
			_safe_connect(_grid, "cell_content_cleared", _on_cell_content_cleared)
		
		# Connect to planet spawner signals
		if _planet_spawner.has_signal("planet_spawned"):
			_safe_connect(_planet_spawner, "planet_spawned", _on_planet_spawned)
		
		# Wait an additional frame to ensure both are fully initialized
		await get_tree().process_frame
		
		_dependencies_initialized = true
		dependencies_found.emit()
		if debug_mode:
			print("WorldGenerator: All dependencies found and initialized.")
	else:
		# Try again after a frame
		call_deferred("_find_dependencies")

# Safely connect signals and track them for cleanup
func _safe_connect(source: Object, signal_name: String, callable: Callable) -> void:
	if source.has_signal(signal_name) and not source.is_connected(signal_name, callable):
		source.connect(signal_name, callable)
		_connected_signals.append({
			"source": source,
			"signal_name": signal_name,
			"callable": callable
		})

# Handle grid content being cleared
func _on_cell_content_cleared(cell_coords: Vector2i) -> void:
	if debug_mode:
		print("WorldGenerator: Content in cell ", cell_coords, " was cleared")

# Handle planet spawned
func _on_planet_spawned(planet: Node, _coords: Vector2i) -> void:
	if is_instance_valid(planet) and not _generated_planets.has(planet):
		_generated_planets.append(planet)

# PUBLIC API

## Generate a procedural world with the specified parameters
## This is a coroutine that may need to wait for dependencies
func generate_world(params: Dictionary = {}) -> void:
	if _generation_in_progress:
		push_warning("WorldGenerator: World generation already in progress")
		return
	
	# If dependencies aren't initialized yet, wait for them
	if not _dependencies_initialized:
		if debug_mode:
			print("WorldGenerator: Waiting for dependencies before generating world...")
		await dependencies_found
	
	# Double-check dependencies are still valid
	if not is_instance_valid(_grid) or not is_instance_valid(_planet_spawner):
		push_error("WorldGenerator: Dependencies became invalid, can't generate world")
		return
	
	_generation_in_progress = true
	world_generation_started.emit()
	
	# Extract parameters or use defaults
	var cell_size = params.get("cell_size", default_cell_size)
	var grid_size = params.get("grid_size", default_grid_size)
	var seed_value = params.get("seed", 0)
	
	# If no seed provided, generate one
	if seed_value == 0:
		randomize()
		seed_value = randi()
	
	_current_seed = seed_value
	
	# Update the global seed if SeedManager is available
	if Engine.has_singleton("SeedManager") and use_deterministic_seed:
		var seed_manager = Engine.get_singleton("SeedManager")
		if seed_manager.has_method("set_seed"):
			seed_manager.set_seed(seed_value)
	
	# Clean up previous generation
	_clean_previous_generation()
	
	# Create the grid
	if is_instance_valid(_grid):
		_grid.create_grid(cell_size, grid_size)
	else:
		push_error("WorldGenerator: No grid available for world generation")
		_generation_in_progress = false
		return
	
	# Now let's populate the grid
	# Wait a frame to make sure the grid is ready
	await get_tree().process_frame
	
	# Populate the grid
	await _populate_grid(params)
	
	# Generation complete
	_generation_in_progress = false
	world_generation_completed.emit()

## Generate a single planet in a specific cell
## This is a coroutine that may need to wait for dependencies
func generate_planet_in_cell(cell_coords: Vector2i, planet_params: Dictionary = {}) -> Node2D:
	# If dependencies aren't initialized yet, wait for them
	if not _dependencies_initialized:
		if debug_mode:
			print("WorldGenerator: Waiting for dependencies before generating planet...")
		await dependencies_found
	
	# Verify dependencies are still valid
	if not is_instance_valid(_grid) or not is_instance_valid(_planet_spawner):
		push_error("WorldGenerator: Missing dependencies (grid or planet spawner)")
		return null
	
	# Verify the cell is valid
	if not _grid.is_valid_cell(cell_coords):
		push_error("WorldGenerator: Invalid cell coordinates: ", cell_coords)
		return null
	
	# Get cell content - FIXED: Improved instance validity checking
	var existing_content = _grid.get_cell_content(cell_coords)
	if existing_content != null:
		if is_instance_valid(existing_content):
			# Only consider it occupied if the content still exists
			if debug_mode:
				print("WorldGenerator: Cell already contains valid content: ", cell_coords)
			if existing_content is Planet:
				return existing_content
			return null
		else:
			# Content reference exists but is invalid - cell is actually free
			if debug_mode:
				print("WorldGenerator: Cell had invalid content reference, proceeding with generation")
	
	# Determine planet category and theme
	var category = planet_params.get("category", "random")
	var theme = planet_params.get("theme", "random")
	
	# Spawn the planet - this may be an async operation internally,
	# so we'll add extra safety by waiting a frame
	await get_tree().process_frame
	
	var planet = _planet_spawner.spawn_planet_at_grid_position(cell_coords, category, theme)
	
	# Wait a frame to let the planet initialize properly
	await get_tree().process_frame
	
	if is_instance_valid(planet):
		# Add planet to our tracking list if not already there
		if not _generated_planets.has(planet):
			_generated_planets.append(planet)
		
		# Emit signal
		cell_generated.emit(cell_coords, "planet")
		
		return planet
	
	return null

## Clean up the generated world
func clean_world() -> void:
	_clean_previous_generation()
	
	# Reset the grid
	if is_instance_valid(_grid):
		_grid.clear_grid_data()

## Get the current world seed
func get_current_seed() -> int:
	return _current_seed

## Set a new world seed
func set_world_seed(new_seed: int) -> void:
	_current_seed = new_seed
	
	# Update the global seed if SeedManager is available
	if Engine.has_singleton("SeedManager") and use_deterministic_seed:
		var seed_manager = Engine.get_singleton("SeedManager")
		if seed_manager.has_method("set_seed"):
			seed_manager.set_seed(new_seed)

## Get all generated planets (filtering out invalid instances)
func get_generated_planets() -> Array:
	# Filter out any invalid references
	var valid_planets = []
	for planet in _generated_planets:
		if is_instance_valid(planet):
			valid_planets.append(planet)
	
	# Update our internal list if it contained invalid references
	if valid_planets.size() != _generated_planets.size():
		_generated_planets = valid_planets
	
	return valid_planets

## Get the grid size
func get_grid_size() -> int:
	if is_instance_valid(_grid):
		return _grid.grid_size
	return default_grid_size

## Get the cell size
func get_cell_size() -> int:
	if is_instance_valid(_grid):
		return _grid.cell_size
	return default_cell_size

# PRIVATE METHODS

# Now properly marked as a coroutine since it uses await
func _populate_grid(params: Dictionary) -> void:
	"""Populate the grid with planets and other content"""
	# Extract or use default probabilities
	var planet_prob = params.get("planet_density", planet_density)
	var terran_prob = params.get("terran_probability", terran_probability)
	
	# Create a deterministic RNG for consistent generation
	var rng = RandomNumberGenerator.new()
	rng.seed = _current_seed
	
	# Generate planets
	var grid_size = get_grid_size()
	
	for x in range(grid_size):
		for y in range(grid_size):
			var cell_coords = Vector2i(x, y)
			
			# Check if we should place a planet here
			if rng.randf() < planet_prob:
				# Determine planet type
				var category = "gaseous"
				if rng.randf() < terran_prob:
					category = "terran"
				
				# For terran planets, randomly choose a theme
				var theme = "random"
				if category == "terran":
					var terran_themes = ["arid", "ice", "lava", "lush", "desert", "alpine", "ocean"]
					theme = terran_themes[rng.randi() % terran_themes.size()]
				
				# Generate planet params
				var planet_params = {
					"category": category,
					"theme": theme,
					"seed_offset": x * 1000 + y * 100  # Make seed unique for each position
				}
				
				# Generate the planet - we want to spawn planets in sequence to avoid
				# overloading the system, so we'll await each one
				await generate_planet_in_cell(cell_coords, planet_params)
				
				# Brief pause to allow processing between planet generation
				if (x + y) % 3 == 0:  # Only pause occasionally
					await get_tree().process_frame
			else:
				# Empty cell or other content in the future
				if is_instance_valid(_grid):
					_grid.set_cell_content(cell_coords, "empty")

func _clean_previous_generation() -> void:
	"""Clean up previously generated content"""
	# Clean up planets, but first make a copy since we're modifying the array
	var planets_to_clean = _generated_planets.duplicate()
	
	for planet in planets_to_clean:
		if is_instance_valid(planet):
			planet.queue_free()
	
	_generated_planets.clear()
	
	# Reset the grid data
	if is_instance_valid(_grid):
		_grid.clear_grid_data()
