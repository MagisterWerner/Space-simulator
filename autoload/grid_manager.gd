extends Node

signal player_cell_changed(old_cell, new_cell)
signal seed_initialized

var game_settings = null
var world_grid = null

# Fallback values
var cell_size = 1024
var grid_size = 10

var _player_current_cell = Vector2i(-1, -1)
var _player_last_check_position = Vector2.ZERO
var _grid_initialized = false
var _seed_ready = false
var _seed_value = 12345

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_find_game_systems")

func _find_game_systems():
	# Wait one frame
	await get_tree().process_frame
	
	# Find GameSettings
	var main_scene = get_tree().current_scene
	game_settings = main_scene.get_node_or_null("GameSettings")
	
	# Connect to GameSettings for seed changes
	if game_settings and game_settings.has_signal("seed_changed"):
		if not game_settings.is_connected("seed_changed", _on_seed_changed):
			game_settings.connect("seed_changed", _on_seed_changed)
	
	# Connect to SeedManager
	_connect_to_seed_manager()
	
	if game_settings:
		# Update local variables
		cell_size = game_settings.grid_cell_size
		grid_size = game_settings.grid_size
	
	# Find the world grid
	_find_world_grid()
	
	_grid_initialized = true
	seed_initialized.emit()

func _process(_delta):
	_update_player_cell()

func _connect_to_seed_manager():
	if has_node("/root/SeedManager"):
		# Connect to seed changes
		if SeedManager.has_signal("seed_changed") and not SeedManager.is_connected("seed_changed", _on_seed_changed):
			SeedManager.connect("seed_changed", _on_seed_changed)
		
		# Wait for initialization if needed
		if SeedManager.has_method("is_initialized") and not SeedManager.is_initialized:
			if SeedManager.has_signal("seed_initialized"):
				SeedManager.seed_initialized.connect(_on_seed_manager_initialized)
		else:
			_seed_ready = true
			_seed_value = SeedManager.get_seed()
	elif game_settings:
		_seed_ready = false
		_seed_value = game_settings.get_seed()

func _on_seed_manager_initialized():
	_seed_ready = true
	if has_node("/root/SeedManager"):
		_seed_value = SeedManager.get_seed()

func _on_seed_changed(new_seed):
	_seed_value = new_seed
	_seed_ready = true

func _find_world_grid():
	# Try to find the grid in various ways
	var grids = get_tree().get_nodes_in_group("world_grid")
	if not grids.is_empty():
		world_grid = grids[0]
		if world_grid and not game_settings:
			cell_size = world_grid.cell_size
			grid_size = world_grid.grid_size
		return
	
	# Try to find directly in the Main scene
	var main = get_node_or_null("/root/Main")
	if main:
		world_grid = main.get_node_or_null("WorldGrid")
		if world_grid and not game_settings:
			cell_size = world_grid.cell_size
			grid_size = world_grid.grid_size

func _update_player_cell():
	var player_ships = get_tree().get_nodes_in_group("player")
	if player_ships.is_empty():
		return
	
	var player_ship = player_ships[0]
	var player_position = player_ship.global_position
	
	# Only check if player has moved significantly
	if player_position.distance_to(_player_last_check_position) < cell_size / 4.0:
		return
	
	_player_last_check_position = player_position
	
	# Calculate cell coordinates
	var cell_coords = world_to_cell(player_position)
	
	# Check if cell changed
	if cell_coords != _player_current_cell:
		var old_cell = _player_current_cell
		_player_current_cell = cell_coords
		player_cell_changed.emit(old_cell, _player_current_cell)

# Get player's current cell coordinates
func get_player_cell():
	return _player_current_cell

# Convert world position to cell coordinates
func world_to_cell(world_position):
	# Use GameSettings if available
	if game_settings and game_settings.has_method("get_cell_coords"):
		return game_settings.get_cell_coords(world_position)
	
	# Use world_grid if available
	if world_grid and world_grid.has_method("get_cell_coords"):
		return world_grid.get_cell_coords(world_position)
	
	# Calculate manually
	var grid_offset = Vector2(-cell_size * grid_size / 2.0, -cell_size * grid_size / 2.0)
	var local_pos = world_position - grid_offset
	return Vector2i(
		int(floor(local_pos.x / cell_size)),
		int(floor(local_pos.y / cell_size))
	)

# Convert cell coordinates to world position
func cell_to_world(cell_coords):
	# Use GameSettings if available
	if game_settings and game_settings.has_method("get_cell_world_position"):
		return game_settings.get_cell_world_position(cell_coords)
	
	# Use world_grid if available
	if world_grid and world_grid.has_method("get_cell_center"):
		return world_grid.get_cell_center(cell_coords)
	
	# Calculate manually
	var grid_offset = Vector2(-cell_size * grid_size / 2.0, -cell_size * grid_size / 2.0)
	return grid_offset + Vector2(
		cell_coords.x * cell_size + cell_size / 2.0,
		cell_coords.y * cell_size + cell_size / 2.0
	)

# Check if cell coordinates are valid
func is_valid_cell(cell_coords):
	if game_settings and game_settings.has_method("is_valid_cell"):
		return game_settings.is_valid_cell(cell_coords)
	
	return (
		cell_coords.x >= 0 and cell_coords.x < grid_size and
		cell_coords.y >= 0 and cell_coords.y < grid_size
	)

# Get neighboring cell coordinates
func get_neighbor_cells(cell_coords, include_diagonals = false):
	var neighbors = []
	
	# Cardinal directions
	var directions = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]
	
	# Add diagonals if requested
	if include_diagonals:
		directions.append_array([
			Vector2i(1, 1),
			Vector2i(1, -1),
			Vector2i(-1, 1),
			Vector2i(-1, -1)
		])
	
	# Check each direction
	for dir in directions:
		var neighbor = cell_coords + dir
		if is_valid_cell(neighbor):
			neighbors.append(neighbor)
	
	return neighbors

# Get Manhattan distance between two cells
func get_cell_distance(from_cell, to_cell):
	return abs(from_cell.x - to_cell.x) + abs(from_cell.y - to_cell.y)

# Generate a deterministic value for a cell
func get_cell_value(cell_coords, min_val, max_val, parameter_id = 0):
	# Use SeedManager if available
	if _seed_ready and has_node("/root/SeedManager"):
		var object_id = cell_coords.x * 10000 + cell_coords.y
		return SeedManager.get_random_value(object_id, min_val, max_val, parameter_id)
		
	elif game_settings and game_settings.has_method("get_random_value"):
		var object_id = cell_coords.x * 10000 + cell_coords.y
		return game_settings.get_random_value(object_id, min_val, max_val, parameter_id)
		
	else:
		# Simple hash-based random value
		var rng = RandomNumberGenerator.new()
		rng.seed = hash(str(_seed_value) + str(cell_coords) + str(parameter_id))
		return min_val + rng.randf() * (max_val - min_val)

# Get a deterministic integer for a cell
func get_cell_int(cell_coords, min_val, max_val, parameter_id = 0):
	# Use SeedManager if available
	if _seed_ready and has_node("/root/SeedManager"):
		var object_id = cell_coords.x * 10000 + cell_coords.y
		return SeedManager.get_random_int(object_id, min_val, max_val, parameter_id)
		
	elif game_settings and game_settings.has_method("get_random_int"):
		var object_id = cell_coords.x * 10000 + cell_coords.y
		return game_settings.get_random_int(object_id, min_val, max_val, parameter_id)
		
	else:
		# Simple hash-based random value
		var rng = RandomNumberGenerator.new()
		rng.seed = hash(str(_seed_value) + str(cell_coords) + str(parameter_id))
		return rng.randi_range(min_val, max_val)
