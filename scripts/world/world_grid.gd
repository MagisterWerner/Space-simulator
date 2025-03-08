# scripts/world/world_grid.gd
# Draws a grid in the game world that remains fixed as the player moves
extends Node2D

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

func _ready() -> void:
	# Make this node available globally if needed
	add_to_group("world_grid")
	
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
	
	if debug_mode:
		print("WorldGrid: Initialized with cell size ", cell_size, " and grid size ", grid_size)

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

# Centers the grid so the player is in the middle
func center_grid_on_player() -> void:
	var player_ships = get_tree().get_nodes_in_group("player")
	if player_ships.is_empty():
		return
		
	var player_ship = player_ships[0]
	
	# Calculate grid center
	var grid_center = _grid_total_size / 2.0
	
	# Reposition grid so player is at the center
	position = player_ship.global_position - grid_center
	
	queue_redraw()
	
	if debug_mode:
		print("WorldGrid: Centered grid on player at position ", player_ship.global_position)

# Reset the grid to its default position
func reset_grid() -> void:
	position = -_grid_total_size / 2
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
