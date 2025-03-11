# scripts/managers/grid_manager.gd
# Utility singleton for grid-based functionality, now using GameSettings
extends Node

signal player_cell_changed(old_cell, new_cell)

var game_settings: GameSettings = null
var world_grid: Node2D = null

# Fallback values if settings not available
var cell_size: int = 1024
var grid_size: int = 10

var _player_current_cell: Vector2i = Vector2i(-1, -1)
var _player_last_check_position: Vector2 = Vector2.ZERO
var _grid_initialized: bool = false
var _seed_ready: bool = false

func _ready() -> void:
	# Process mode to keep working during pause
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Find the world grid after a frame delay to ensure it's initialized
	call_deferred("_find_game_systems")

func _find_game_systems() -> void:
	# Wait one frame to ensure grid is initialized
	await get_tree().process_frame
	
	# Find GameSettings in the main scene
	var main_scene = get_tree().current_scene
	game_settings = main_scene.get_node_or_null("GameSettings")
	
	# Check for SeedManager dependency
	_seed_ready = has_node("/root/SeedManager")
	
	if game_settings:
		# Update our local variables from settings
		cell_size = game_settings.grid_cell_size
		grid_size = game_settings.grid_size
		
		if game_settings.debug_mode:
			print("GridManager: Found GameSettings, using configured values")
			print("GridManager: Cell size: ", cell_size, ", Grid size: ", grid_size)
	
	# Find the world grid
	_find_world_grid()
	
	_grid_initialized = true

func _process(_delta: float) -> void:
	# Check player position and update cell information
	_update_player_cell()

func _find_world_grid() -> void:
	# Try to find the grid in various ways
	var grids = get_tree().get_nodes_in_group("world_grid")
	if not grids.is_empty():
		world_grid = grids[0]
		if world_grid:
			# Update our cache from the grid's values if not using GameSettings
			if not game_settings:
				cell_size = world_grid.cell_size
				grid_size = world_grid.grid_size
		return
	
	# Try to find directly in the Main scene
	var main = get_node_or_null("/root/Main")
	if main:
		world_grid = main.get_node_or_null("WorldGrid")
		if world_grid:
			# Update our cache from the grid's values if not using GameSettings
			if not game_settings:
				cell_size = world_grid.cell_size
				grid_size = world_grid.grid_size
			return
	
	# If grid not found, log message
	print("GridManager: WorldGrid not found, using cached values")

func _update_player_cell() -> void:
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
	var cell_coords: Vector2i
	
	# First use GameSettings if available
	if game_settings:
		cell_coords = game_settings.get_cell_coords(player_position)
	# Then try world grid if available
	elif world_grid and world_grid.has_method("get_cell_coords"):
		cell_coords = world_grid.get_cell_coords(player_position)
	else:
		# Calculate manually if grid not available
		var grid_offset = Vector2(-cell_size * grid_size / 2.0, -cell_size * grid_size / 2.0)
		var local_pos = player_position - grid_offset
		cell_coords = Vector2i(
			int(floor(local_pos.x / cell_size)),
			int(floor(local_pos.y / cell_size))
		)
	
	# Check if cell changed
	if cell_coords != _player_current_cell:
		var old_cell = _player_current_cell
		_player_current_cell = cell_coords
		
		# Emit signal
		player_cell_changed.emit(old_cell, _player_current_cell)
		
		# Debug info
		if (game_settings and game_settings.debug_mode) or (not game_settings and _grid_initialized):
			if old_cell.x >= 0 and old_cell.y >= 0:
				print("Player moved from cell (%d,%d) to (%d,%d)" % [
					old_cell.x, old_cell.y, 
					cell_coords.x, cell_coords.y
				])
			else:
				print("Player entered cell (%d,%d)" % [cell_coords.x, cell_coords.y])

# Get player's current cell coordinates
func get_player_cell() -> Vector2i:
	_update_player_cell()
	return _player_current_cell

# Convert world position to cell coordinates
func world_to_cell(world_position: Vector2) -> Vector2i:
	# First use GameSettings if available
	if game_settings:
		return game_settings.get_cell_coords(world_position)
	# Then try world grid if available
	elif world_grid and world_grid.has_method("get_cell_coords"):
		return world_grid.get_cell_coords(world_position)
	
	# Calculate manually if grid not available
	var grid_offset = Vector2(-cell_size * grid_size / 2.0, -cell_size * grid_size / 2.0)
	var local_pos = world_position - grid_offset
	return Vector2i(
		int(floor(local_pos.x / cell_size)),
		int(floor(local_pos.y / cell_size))
	)

# Convert cell coordinates to world position (center of cell)
func cell_to_world(cell_coords: Vector2i) -> Vector2:
	# First use GameSettings if available
	if game_settings:
		return game_settings.get_cell_world_position(cell_coords)
	# Then try world grid if available
	elif world_grid and world_grid.has_method("get_cell_center"):
		return world_grid.get_cell_center(cell_coords)
	
	# Calculate manually if grid not available
	var grid_offset = Vector2(-cell_size * grid_size / 2.0, -cell_size * grid_size / 2.0)
	return grid_offset + Vector2(
		cell_coords.x * cell_size + cell_size / 2.0,
		cell_coords.y * cell_size + cell_size / 2.0
	)

# Check if cell coordinates are valid (within grid bounds)
func is_valid_cell(cell_coords: Vector2i) -> bool:
	if game_settings:
		return game_settings.is_valid_cell(cell_coords)
	
	return (
		cell_coords.x >= 0 and cell_coords.x < grid_size and
		cell_coords.y >= 0 and cell_coords.y < grid_size
	)

# Get neighboring cell coordinates
func get_neighbor_cells(cell_coords: Vector2i, include_diagonals: bool = false) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	
	# Cardinal directions
	var directions = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]
	
	# Add diagonals if requested
	if include_diagonals:
		directions.append(Vector2i(1, 1))
		directions.append(Vector2i(1, -1))
		directions.append(Vector2i(-1, 1))
		directions.append(Vector2i(-1, -1))
	
	# Check each direction
	for dir in directions:
		var neighbor = cell_coords + dir
		if is_valid_cell(neighbor):
			neighbors.append(neighbor)
	
	return neighbors

# Get Manhattan distance between two cells
func get_cell_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	return abs(from_cell.x - to_cell.x) + abs(from_cell.y - to_cell.y)

# Generate a deterministic value for a cell
# This is useful for procedural generation that needs to be consistent
func get_cell_value(cell_coords: Vector2i, min_val: float, max_val: float, parameter_id: int = 0) -> float:
	# First try to use SeedManager for consistency
	if _seed_ready and has_node("/root/SeedManager"):
		# Create a deterministic object ID from cell coordinates
		var object_id = cell_coords.x * 10000 + cell_coords.y
		return SeedManager.get_random_value(object_id, min_val, max_val, parameter_id)
	elif game_settings:
		# Fall back to GameSettings
		var object_id = cell_coords.x * 10000 + cell_coords.y
		return game_settings.get_random_value(object_id, min_val, max_val, parameter_id)
	else:
		# Last resort - create a simple hash-based random value
		var rng = RandomNumberGenerator.new()
		rng.seed = hash(str(cell_coords) + str(parameter_id))
		return min_val + rng.randf() * (max_val - min_val)

# Get a deterministic integer for a cell
func get_cell_int(cell_coords: Vector2i, min_val: int, max_val: int, parameter_id: int = 0) -> int:
	# First try to use SeedManager for consistency
	if _seed_ready and has_node("/root/SeedManager"):
		# Create a deterministic object ID from cell coordinates
		var object_id = cell_coords.x * 10000 + cell_coords.y
		return SeedManager.get_random_int(object_id, min_val, max_val, parameter_id)
	elif game_settings:
		# Fall back to GameSettings
		var object_id = cell_coords.x * 10000 + cell_coords.y
		return game_settings.get_random_int(object_id, min_val, max_val, parameter_id)
	else:
		# Last resort - create a simple hash-based random value
		var rng = RandomNumberGenerator.new()
		rng.seed = hash(str(cell_coords) + str(parameter_id))
		return rng.randi_range(min_val, max_val)
