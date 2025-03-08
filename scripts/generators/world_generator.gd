# scripts/world/world_generator.gd
# A utility class that integrates the grid and planet systems
# to enable procedural world generation
extends Node
class_name WorldGenerator

signal world_generation_started
signal world_generation_completed
signal cell_generated(coords, content_type)

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

func _ready() -> void:
	# Find grid and planet spawner
	call_deferred("_find_dependencies")

func _find_dependencies() -> void:
	"""Find required dependencies for world generation"""
	
	# Look for WorldGrid
	var grids = get_tree().get_nodes_in_group("world_grid")
	if not grids.is_empty():
		_grid = grids[0]
	else:
		# Try to find in current scene
		_grid = get_node_or_null("../WorldGrid")
		
		if not _grid:
			# Create a new grid if needed
			_grid = WorldGrid.new()
			_grid.cell_size = default_cell_size
			_grid.grid_size = default_grid_size
			add_child(_grid)
	
	# Look for PlanetSpawner
	var spawners = get_tree().get_nodes_in_group("planet_spawner")
	if not spawners.is_empty():
		_planet_spawner = spawners[0]
	else:
		# Try to find in current scene
		_planet_spawner = get_node_or_null("../PlanetSpawner")
		
		if not _planet_spawner:
			# Create a new spawner if needed
			_planet_spawner = PlanetSpawner.new()
			add_child(_planet_spawner)
	
	if debug_mode:
		print("WorldGenerator initialized with grid: ", _grid != null, ", planet spawner: ", _planet_spawner != null)

# PUBLIC API

## Generate a procedural world with the specified parameters
func generate_world(params: Dictionary = {}) -> void:
	if _generation_in_progress:
		push_warning("WorldGenerator: World generation already in progress")
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
	if has_node("/root/SeedManager") and use_deterministic_seed:
		SeedManager.set_seed(seed_value)
	
	# Clean up previous generation
	_clean_previous_generation()
	
	# Create the grid
	if _grid:
		_grid.create_grid(cell_size, grid_size)
	else:
		push_error("WorldGenerator: No grid available for world generation")
		_generation_in_progress = false
		return
	
	# Now let's populate the grid
	call_deferred("_populate_grid", params)

## Generate a single planet in a specific cell
func generate_planet_in_cell(cell_coords: Vector2i, planet_params: Dictionary = {}) -> Node2D:
	if not _grid or not _planet_spawner:
		push_error("WorldGenerator: Missing dependencies (grid or planet spawner)")
		return null
	
	# Verify the cell is valid
	if not _grid.is_valid_cell(cell_coords):
		push_error("WorldGenerator: Invalid cell coordinates: ", cell_coords)
		return null
	
	# Get cell content
	var existing_content = _grid.get_cell_content(cell_coords)
	if existing_content and is_instance_valid(existing_content):
		push_warning("WorldGenerator: Cell already contains content: ", cell_coords)
		if existing_content is Planet:
			return existing_content
		return null
	
	# Determine planet category and theme
	var category = planet_params.get("category", "random")
	var theme = planet_params.get("theme", "random")
	
	# Spawn the planet
	var planet = _planet_spawner.spawn_planet_at_grid_position(cell_coords, category, theme)
	if planet:
		_generated_planets.append(planet)
		cell_generated.emit(cell_coords, "planet")
	
	return planet

## Clean up the generated world
func clean_world() -> void:
	_clean_previous_generation()
	
	# Reset the grid
	if _grid:
		_grid.clear_grid_data()

## Get the current world seed
func get_current_seed() -> int:
	return _current_seed

## Set a new world seed
func set_world_seed(new_seed: int) -> void:
	_current_seed = new_seed
	
	# Update the global seed if SeedManager is available
	if has_node("/root/SeedManager") and use_deterministic_seed:
		SeedManager.set_seed(new_seed)

## Get all generated planets
func get_generated_planets() -> Array:
	return _generated_planets

## Get the grid size
func get_grid_size() -> int:
	return _grid.grid_size if _grid else default_grid_size

## Get the cell size
func get_cell_size() -> int:
	return _grid.cell_size if _grid else default_cell_size

# PRIVATE METHODS

func _populate_grid(params: Dictionary) -> void:
	"""Populate the grid with planets and other content"""
	# Extract or use default probabilities
	var planet_prob = params.get("planet_density", planet_density)
	var terran_prob = params.get("terran_probability", terran_probability)
	
	# Create a deterministic RNG for consistent generation
	var rng = RandomNumberGenerator.new()
	rng.seed = _current_seed
	
	# Generate planets
	for x in range(_grid.grid_size):
		for y in range(_grid.grid_size):
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
				
				# Generate the planet
				generate_planet_in_cell(cell_coords, planet_params)
			else:
				# Empty cell or other content in the future
				_grid.set_cell_content(cell_coords, "empty")
	
	# Generation complete
	_generation_in_progress = false
	world_generation_completed.emit()

func _clean_previous_generation() -> void:
	"""Clean up previously generated content"""
	# Clean up planets
	for planet in _generated_planets:
		if is_instance_valid(planet):
			planet.queue_free()
	
	_generated_planets.clear()
	
	# Reset the grid data
	if _grid:
		_grid.clear_grid_data()
