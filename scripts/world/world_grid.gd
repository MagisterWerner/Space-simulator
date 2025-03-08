# scripts/world/world_grid.gd
extends Node2D
class_name WorldGrid

signal grid_initialized

## Grid cell size in pixels
@export var cell_size: int = 1024

## Grid dimensions (number of cells in each direction)
@export var grid_size: int = 10

## Grid line color
@export var grid_color: Color = Color.CYAN

## Grid line width
@export var line_width: float = 2.0

## Opacity of the grid lines
@export var grid_opacity: float = 0.5

## Whether to show debug information
@export var debug_mode: bool = false

# Internal variables
var _camera: Camera2D = null
var _viewport_size: Vector2 = Vector2.ZERO
var _grid_total_size: Vector2 = Vector2.ZERO
var _initialized: bool = false
var _grid_cells: Dictionary = {}

func _ready() -> void:
	# Make this node available globally if needed
	add_to_group("world_grid")
	
	# Initialize grid after waiting for the scene to be ready
	call_deferred("initialize_grid")

func initialize_grid() -> void:
	if _initialized:
		return
	
	# Calculate the total grid size in pixels
	_grid_total_size = Vector2(cell_size, cell_size) * grid_size
	
	# Center the grid in the world
	position = -_grid_total_size / 2.0
	
	# Initialize viewport size
	_viewport_size = get_viewport_rect().size
	
	# Find the camera
	_find_camera()
	
	# Force update when ready
	queue_redraw()
	
	_initialized = true
	grid_initialized.emit()
	
	if debug_mode:
		print("WorldGrid: Initialized with cell size ", cell_size, " and grid size ", grid_size, 
			", total size: ", _grid_total_size)
		print("WorldGrid: Positioned at ", position)

func _process(_delta: float) -> void:
	# Only redraw if initialized
	if not _initialized:
		return
		
	# Update viewport size if it changed
	var current_viewport_size = get_viewport_rect().size
	if current_viewport_size != _viewport_size:
		_viewport_size = current_viewport_size
		queue_redraw()
	
	# Only redraw when camera moves
	if _camera and is_instance_valid(_camera):
		queue_redraw()

func _draw() -> void:
	if not _initialized:
		return
	
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
	
	if debug_mode:
		# Draw grid bounds for debugging
		var grid_rect = Rect2(Vector2.ZERO, _grid_total_size)
		draw_rect(grid_rect, Color.RED, false, 3.0)
		
		# Draw grid coordinates
		#for cell_key in _grid_cells:
			#var grid_pos = _grid_cells[cell_key]
			#var cell_position = get_cell_center(grid_pos)
			#var text = str(grid_pos.x) + "," + str(grid_pos.y)
			#draw_string(get_theme_default_font(), cell_position, text, HORIZONTAL_ALIGNMENT_CENTER)

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

# Register a cell as occupied (for planet placement)
func register_cell(cell_coords: Vector2i, entity_name: String = "") -> void:
	var cell_key = str(cell_coords.x) + "," + str(cell_coords.y)
	_grid_cells[cell_key] = {"coords": cell_coords, "entity": entity_name}
	
	if debug_mode:
		print("WorldGrid: Registered cell ", cell_coords, " with entity: ", entity_name)
	
	# Force redraw to update debug view
	if debug_mode:
		queue_redraw()

# Check if a cell is occupied
func is_cell_occupied(cell_coords: Vector2i) -> bool:
	var cell_key = str(cell_coords.x) + "," + str(cell_coords.y)
	return _grid_cells.has(cell_key)

# Get the number of occupied cells
func get_occupied_cell_count() -> int:
	return _grid_cells.size()

# Reset the grid to its default position
func reset_grid() -> void:
	position = -_grid_total_size / 2
	_grid_cells.clear()
	queue_redraw()

# Get the cell coordinates for a given world position
func get_cell_coords(world_position: Vector2) -> Vector2i:
	var local_pos = world_position - position
	var cell_x = int(floor(local_pos.x / cell_size))
	var cell_y = int(floor(local_pos.y / cell_size))
	return Vector2i(cell_x, cell_y)

# Get the world position of a cell's top-left corner
func get_cell_position(cell_coords: Vector2i) -> Vector2:
	return position + Vector2(cell_coords.x * cell_size, cell_coords.y * cell_size)

# Get the world position of a cell's center
func get_cell_center(cell_coords: Vector2i) -> Vector2:
	return get_cell_position(cell_coords) + Vector2(cell_size / 2.0, cell_size / 2.0)

# Check if cell coordinates are valid (within grid bounds)
func is_valid_cell(cell_coords: Vector2i) -> bool:
	return cell_coords.x >= 0 and cell_coords.x < grid_size and cell_coords.y >= 0 and cell_coords.y < grid_size

# Get a list of all valid cells
func get_all_valid_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(grid_size):
		for y in range(grid_size):
			cells.append(Vector2i(x, y))
	return cells

# Update grid configuration at runtime
func configure(new_size: int, new_cell_size: int, new_color: Color, new_width: float, new_opacity: float) -> void:
	var changed = false
	
	if grid_size != new_size:
		grid_size = new_size
		changed = true
	
	if cell_size != new_cell_size:
		cell_size = new_cell_size
		changed = true
	
	grid_color = new_color
	line_width = new_width
	grid_opacity = new_opacity
	
	if changed:
		# Recalculate grid size and position
		_grid_total_size = Vector2(cell_size, cell_size) * grid_size
		position = -_grid_total_size / 2.0
		_grid_cells.clear()
	
	queue_redraw()
