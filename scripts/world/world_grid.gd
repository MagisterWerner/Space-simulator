# scripts/world/world_grid.gd
# A flexible grid system that provides both visual representation and spatial organization
# for procedural world generation.
extends Node2D
class_name WorldGrid

## Grid cell size in pixels
@export var cell_size: int = 1024:
	set(value):
		cell_size = value
		_update_grid_properties()

## Grid dimensions (number of cells in each direction)
@export var grid_size: int = 10:
	set(value):
		grid_size = value
		_update_grid_properties()
		
## Grid line color
@export var grid_color: Color = Color.CYAN

## Grid line width
@export var line_width: float = 2.0

## Opacity of the grid lines
@export var grid_opacity: float = 0.5

## Whether to show cell coordinates for debugging
@export var show_cell_coords: bool = false

## Whether to show debug information
@export var debug_mode: bool = false

# Signal emitted when grid is initialized or changed
signal grid_initialized(cell_size, grid_size)
signal grid_updated(cell_size, grid_size)
signal cell_clicked(cell_coords)

# Internal variables
var _camera: Camera2D = null
var _viewport_size: Vector2 = Vector2.ZERO
var _grid_total_size: Vector2 = Vector2.ZERO
var _initialized: bool = false
var _grid_data: Dictionary = {}  # Can store custom data for each cell

func _ready() -> void:
	# Make this node available globally if needed
	add_to_group("world_grid")
	
	# Initialize grid properties
	_update_grid_properties()
	
	# Initialize viewport size
	_viewport_size = get_viewport_rect().size
	
	# Find the camera
	_find_camera()
	
	# Force update when ready
	queue_redraw()
	
	# Create empty grid data structure
	_initialize_grid_data()
	
	_initialized = true
	grid_initialized.emit(cell_size, grid_size)
	
	if debug_mode:
		print("WorldGrid: Initialized with cell size ", cell_size, " and grid size ", grid_size)

func _update_grid_properties() -> void:
	# Calculate the total grid size in pixels
	_grid_total_size = Vector2(cell_size, cell_size) * grid_size
	
	# Center the grid in the world
	position = -_grid_total_size / 2.0
	
	if _initialized:
		_initialize_grid_data()
		grid_updated.emit(cell_size, grid_size)
		queue_redraw()

func _process(_delta: float) -> void:
	# Update viewport size if it changed
	var current_viewport_size = get_viewport_rect().size
	if current_viewport_size != _viewport_size:
		_viewport_size = current_viewport_size
		queue_redraw()
	
	# Only redraw when camera moves
	if _camera and is_instance_valid(_camera):
		queue_redraw()

func _draw() -> void:
	if not _camera or not is_instance_valid(_camera):
		_find_camera()
		if not _camera:
			return
	
	# Get visible rectangle based on camera position
	var camera_center = _camera.get_screen_center_position()
	var camera_zoom = _camera.zoom
	var visible_rect = Rect2(
		camera_center - (_viewport_size / (2.0 * camera_zoom)),
		_viewport_size / camera_zoom
	)
	
	# Adjust the visible rect for drawing optimization
	var extended_rect = visible_rect.grow(cell_size)  # Add one cell padding
	
	# Calculate grid bounds for the visible area
	var start_x = floor((extended_rect.position.x - position.x) / cell_size) * cell_size
	var start_y = floor((extended_rect.position.y - position.y) / cell_size) * cell_size
	var end_x = ceil((extended_rect.position.x - position.x + extended_rect.size.x) / cell_size) * cell_size
	var end_y = ceil((extended_rect.position.y - position.y + extended_rect.size.y) / cell_size) * cell_size
	
	# Clamp to grid boundaries
	start_x = max(0, start_x)
	start_y = max(0, start_y)
	end_x = min(grid_size * cell_size, end_x)
	end_y = min(grid_size * cell_size, end_y)
	
	# Draw vertical lines
	for x in range(int(start_x), int(end_x) + cell_size, cell_size):
		if x >= 0 and x <= grid_size * cell_size:
			var from = Vector2(x, start_y)
			var to = Vector2(x, end_y)
			draw_line(from, to, grid_color * Color(1, 1, 1, grid_opacity), line_width)
	
	# Draw horizontal lines
	for y in range(int(start_y), int(end_y) + cell_size, cell_size):
		if y >= 0 and y <= grid_size * cell_size:
			var from = Vector2(start_x, y)
			var to = Vector2(end_x, y)
			draw_line(from, to, grid_color * Color(1, 1, 1, grid_opacity), line_width)
	
	# Debug: Draw cell coordinates
	if show_cell_coords:
		var font = ThemeDB.fallback_font
		var font_size = 16
		
		for x in range(int(start_x / cell_size), int(end_x / cell_size) + 1):
			for y in range(int(start_y / cell_size), int(end_y / cell_size) + 1):
				if x >= 0 and x < grid_size and y >= 0 and y < grid_size:
					var cell_center = get_cell_center(Vector2i(x, y))
					var text = "(%d,%d)" % [x, y]
					var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
					draw_string(font, cell_center - text_size/2, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)
	
	if debug_mode:
		# Draw grid bounds for debugging
		var grid_rect = Rect2(Vector2.ZERO, _grid_total_size)
		draw_rect(grid_rect, Color.RED, false, 3.0)

func _find_camera() -> void:
	# Try to find the camera in various ways
	_camera = get_viewport().get_camera_2d()
	
	if not _camera:
		# Try to find through the player ship
		var player_ships = get_tree().get_nodes_in_group("player")
		if not player_ships.is_empty():
			var player_ship = player_ships[0]
			_camera = player_ship.get_viewport().get_camera_2d()
	
	if not _camera:
		# Try to find through the "Main" scene
		var main = get_node_or_null("/root/Main")
		if main:
			_camera = main.get_node_or_null("Camera2D")
	
	if debug_mode:
		if _camera:
			print("WorldGrid: Found camera at path ", _camera.get_path())
		else:
			push_warning("WorldGrid: Camera not found, grid won't update properly")

func _initialize_grid_data() -> void:
	"""Initialize the grid data dictionary with empty values"""
	_grid_data.clear()
	for x in range(grid_size):
		for y in range(grid_size):
			_grid_data[Vector2i(x, y)] = {
				"type": "empty",
				"content": null,
				"metadata": {}
			}

func _input(event: InputEvent) -> void:
	"""Handle input for grid interaction"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos = get_global_mouse_position()
		var cell_coords = get_cell_coords(mouse_pos)
		
		if is_valid_cell(cell_coords):
			cell_clicked.emit(cell_coords)
			
			if debug_mode:
				print("Cell clicked: ", cell_coords)

# PUBLIC API

## Create a new grid with specified dimensions
func create_grid(new_cell_size: int, new_grid_size: int) -> void:
	cell_size = new_cell_size
	grid_size = new_grid_size
	_update_grid_properties()

## Check if cell coordinates are within the grid boundaries
func is_valid_cell(cell_coords: Vector2i) -> bool:
	return (
		cell_coords.x >= 0 and cell_coords.x < grid_size and
		cell_coords.y >= 0 and cell_coords.y < grid_size
	)

## Get the cell coordinates for a given world position
func get_cell_coords(world_position: Vector2) -> Vector2i:
	var local_pos = world_position - position
	var cell_x = int(floor(local_pos.x / cell_size))
	var cell_y = int(floor(local_pos.y / cell_size))
	return Vector2i(cell_x, cell_y)

## Get the world position of a cell's top-left corner
func get_cell_position(cell_coords: Vector2i) -> Vector2:
	return position + Vector2(cell_coords.x * cell_size, cell_coords.y * cell_size)

## Get the world position of a cell's center
func get_cell_center(cell_coords: Vector2i) -> Vector2:
	return get_cell_position(cell_coords) + Vector2(cell_size / 2.0, cell_size / 2.0)

## Set data for a specific cell
func set_cell_data(cell_coords: Vector2i, key: String, value) -> bool:
	if not is_valid_cell(cell_coords):
		return false
		
	if not _grid_data.has(cell_coords):
		_grid_data[cell_coords] = {}
		
	_grid_data[cell_coords][key] = value
	return true

## Get data for a specific cell
func get_cell_data(cell_coords: Vector2i, key: String, default_value = null):
	if not is_valid_cell(cell_coords) or not _grid_data.has(cell_coords):
		return default_value
		
	return _grid_data[cell_coords].get(key, default_value)

## Set cell content (like a planet, asteroid, etc.)
func set_cell_content(cell_coords: Vector2i, content_type: String, content_node: Node = null) -> bool:
	if not is_valid_cell(cell_coords):
		return false
		
	_grid_data[cell_coords]["type"] = content_type
	_grid_data[cell_coords]["content"] = content_node
	return true

## Get cell content
func get_cell_content(cell_coords: Vector2i) -> Node:
	if not is_valid_cell(cell_coords) or not _grid_data.has(cell_coords):
		return null
		
	return _grid_data[cell_coords].get("content")

## Get all cells of a specific type
func get_cells_by_type(type: String) -> Array:
	var cells = []
	
	for coords in _grid_data.keys():
		if _grid_data[coords].get("type") == type:
			cells.append(coords)
			
	return cells

## Get all neighboring cells (optionally including diagonals)
func get_neighboring_cells(cell_coords: Vector2i, include_diagonals: bool = false) -> Array[Vector2i]:
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

## Get the distance between two cells (Manhattan distance)
func get_cell_distance(from_cell: Vector2i, to_cell: Vector2i) -> int:
	return abs(from_cell.x - to_cell.x) + abs(from_cell.y - to_cell.y)

## Clear all grid data
func clear_grid_data() -> void:
	_initialize_grid_data()

## Reset the grid to its default position
func reset_grid() -> void:
	position = -_grid_total_size / 2
	queue_redraw()

## Centers the grid on a specific world position
func center_grid_on_position(world_position: Vector2) -> void:
	var grid_center = _grid_total_size / 2.0
	position = world_position - grid_center
	queue_redraw()

## Centers the grid so the player is in the middle
func center_grid_on_player() -> void:
	var player_ships = get_tree().get_nodes_in_group("player")
	if player_ships.is_empty():
		return
		
	var player_ship = player_ships[0]
	center_grid_on_position(player_ship.global_position)

## Gets the total grid size in pixels
func get_total_grid_size() -> Vector2:
	return _grid_total_size

## Gets a random valid cell within the grid
func get_random_cell() -> Vector2i:
	var x = randi() % grid_size
	var y = randi() % grid_size
	return Vector2i(x, y)

## Gets a random empty cell within the grid
func get_random_empty_cell() -> Vector2i:
	var empty_cells = get_cells_by_type("empty")
	if empty_cells.size() > 0:
		return empty_cells[randi() % empty_cells.size()]
	
	# Fallback to any random cell if no empty cells
	return get_random_cell()
