# scripts/managers/grid_manager.gd
# Utility singleton for grid-based functionality
extends Node

signal player_cell_changed(old_cell, new_cell)

var cell_size: int = 1024
var grid_size: int = 10

var _world_grid: Node2D = null
var _player_current_cell: Vector2i = Vector2i(-1, -1)
var _player_last_check_position: Vector2 = Vector2.ZERO
var _grid_initialized: bool = false

func _ready() -> void:
	# Process mode to keep working during pause
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Find the world grid after a frame delay to ensure it's initialized
	call_deferred("_find_world_grid")

func _process(_delta: float) -> void:
	# Check player position and update cell information
	_update_player_cell()

func _find_world_grid() -> void:
	# Wait one frame to ensure grid is initialized
	await get_tree().process_frame
	
	# Try to find the grid in various ways
	var grids = get_tree().get_nodes_in_group("world_grid")
	if not grids.is_empty():
		_world_grid = grids[0]
		cell_size = _world_grid.cell_size
		grid_size = _world_grid.grid_size
		_grid_initialized = true
		return
	
	# Try to find directly in the Main scene
	var main = get_node_or_null("/root/Main")
	if main:
		_world_grid = main.get_node_or_null("WorldGrid")
		if _world_grid:
			cell_size = _world_grid.cell_size
			grid_size = _world_grid.grid_size
			_grid_initialized = true
			return
	
	# If grid not found, use default values
	print("GridManager: WorldGrid not found, using default values")

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
	
	if _world_grid and _world_grid.has_method("get_cell_coords"):
		# Use grid's method if available
		cell_coords = _world_grid.get_cell_coords(player_position)
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
		
		# Print debug info
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
	if _world_grid and _world_grid.has_method("get_cell_coords"):
		return _world_grid.get_cell_coords(world_position)
	
	# Calculate manually if grid not available
	var grid_offset = Vector2(-cell_size * grid_size / 2.0, -cell_size * grid_size / 2.0)
	var local_pos = world_position - grid_offset
	return Vector2i(
		int(floor(local_pos.x / cell_size)),
		int(floor(local_pos.y / cell_size))
	)

# Convert cell coordinates to world position (center of cell)
func cell_to_world(cell_coords: Vector2i) -> Vector2:
	if _world_grid and _world_grid.has_method("get_cell_center"):
		return _world_grid.get_cell_center(cell_coords)
	
	# Calculate manually if grid not available
	var grid_offset = Vector2(-cell_size * grid_size / 2.0, -cell_size * grid_size / 2.0)
	return grid_offset + Vector2(
		cell_coords.x * cell_size + cell_size / 2.0,
		cell_coords.y * cell_size + cell_size / 2.0
	)

# Check if cell coordinates are valid (within grid bounds)
func is_valid_cell(cell_coords: Vector2i) -> bool:
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
