extends Node2D

# Grid properties
@export var cell_size: Vector2 = Vector2(64, 64)  # Size of each grid cell
@export var grid_size: Vector2 = Vector2(20, 20)  # Number of cells in grid
@export var grid_color: Color = Color(0.2, 0.2, 0.2, 0.5)  # Grid line color
@export var font_size: int = 12
@export var seed_value: int = 0  # Seed for randomization, exposed in inspector

# Chunk load radius is fixed at 1 to ensure only 9 cells maximum
var chunk_load_radius: int = 1  # This is no longer exported to prevent changing it

# Enum to track different types of cell contents more precisely
enum CellContent { 
	EMPTY, 
	PLANET, 
	ASTEROID, 
	PLANET_AND_ASTEROID  # New state to explicitly prevent mixing
}

# 2D array to store cell contents - now only used for collision/pathfinding
var cell_contents = []

# Track occupied cells to prevent multiple celestial bodies in same cell
var occupied_cells = {}

# Current player cell coordinates
var current_player_cell_x = -1
var current_player_cell_y = -1

# Player state tracking
var was_in_boundary_cell = false
var was_outside_grid = false
var player_immobilized = false
var respawn_timer = 0.0
var last_valid_position = Vector2.ZERO

# Dictionary to track which cells are currently loaded
var loaded_cells = {}

# Signals
signal cell_contents_changed(seed_value)
signal chunks_updated(loaded_cells)

# Called when the node enters the scene tree
func _ready():
	# Initialize the cell contents array
	initialize_cell_contents_array()
	
	# Signal that grid is ready to generate content
	call_deferred("emit_signal", "cell_contents_changed", seed_value)

# Initialize the array structure without populating content
func initialize_cell_contents_array():
	# Recreate the array from scratch
	cell_contents = []
	for y in range(int(grid_size.y)):
		var content_row = []
		for x in range(int(grid_size.x)):
			content_row.append(CellContent.EMPTY)
		cell_contents.append(content_row)
	
	# Reset loaded chunks and force redraw
	loaded_cells.clear()
	queue_redraw()

# Check if a position is valid (within bounds)
func is_valid_position(x, y):
	return x >= 0 and x < grid_size.x and y >= 0 and y < grid_size.y

# Enhanced mark_cell_occupied method
func mark_cell_occupied(x, y, content_type):
	if not is_valid_position(x, y):
		return false
	
	# Get current cell content
	var current_content = get_cell_content(x, y)
	
	# Prevent mixing of different content types
	if current_content != CellContent.EMPTY:
		# If trying to add a different type to an already occupied cell
		if current_content != content_type:
			print("Warning: Cannot occupy cell (%d,%d) - already occupied" % [x, y])
			return false
	
	# Update cell contents array
	if y < cell_contents.size() and x < cell_contents[y].size():
		cell_contents[y][x] = content_type
		occupied_cells[Vector2(x, y)] = content_type
		return true
	
	return false

# Check if a cell is already occupied
func is_cell_occupied(x, y):
	if not is_valid_position(x, y):
		return true
	
	return get_cell_content(x, y) != CellContent.EMPTY

# Clear cell occupancy (useful when regenerating grid)
func clear_cell_occupancy():
	occupied_cells.clear()
	# Reinitialize cell contents array with EMPTY
	for y in range(int(grid_size.y)):
		for x in range(int(grid_size.x)):
			cell_contents[y][x] = CellContent.EMPTY

# Check if a cell is on the boundary (outermost edge)
func is_boundary_cell(x, y):
	return x == 0 or y == 0 or x == grid_size.x - 1 or y == grid_size.y - 1

# Modified set_cell_content to enforce occupancy rules
func set_cell_content(x, y, content_type):
	if not is_valid_position(x, y):
		return false
	
	if y < cell_contents.size() and x < cell_contents[y].size():
		cell_contents[y][x] = content_type
		
		# Update occupied cells tracking
		if content_type != CellContent.EMPTY:
			occupied_cells[Vector2(x, y)] = content_type
		else:
			occupied_cells.erase(Vector2(x, y))
		
		return true
	
	return false

# Get cell content type
func get_cell_content(x, y):
	if is_valid_position(x, y) and y < cell_contents.size() and x < cell_contents[y].size():
		return cell_contents[y][x]
	return CellContent.EMPTY

# Regenerate the grid when properties change
func regenerate():
	clear_cell_occupancy()
	initialize_cell_contents_array()
	emit_signal("cell_contents_changed", seed_value)

# Method to explicitly change the seed from code
func set_seed(new_seed):
	seed_value = new_seed
	print("Setting new seed: ", new_seed)
	
	# Regenerate the grid with new seed
	regenerate()

# Update loaded chunks based on player position
func update_loaded_chunks(center_x, center_y):
	# Clear the currently loaded cells dictionary for a fresh update
	loaded_cells.clear()
	
	# Fixed radius of 1 - only load the current cell and its 8 neighbors (9 cells total)
	# Loop through cells within the chunk_load_radius of the player's position
	for y in range(center_y - 1, center_y + 2):
		for x in range(center_x - 1, center_x + 2):
			if is_valid_position(x, y):
				# Mark this cell as loaded
				loaded_cells[Vector2(x, y)] = true
	
	# Force an immediate visual update
	queue_redraw()
	
	# Emit signal for other nodes to update visibility
	emit_signal("chunks_updated", loaded_cells)
	
	print("Loaded cells updated. Center: (", center_x, ",", center_y, ") - Total loaded: ", loaded_cells.size())

# Draw grid in loaded chunks
func _draw():
	# Only draw grid lines for the loaded chunks
	for cell_pos in loaded_cells.keys():
		var x = cell_pos.x
		var y = cell_pos.y
		
		# Draw cell borders
		var rect_pos = Vector2(x * cell_size.x, y * cell_size.y)
		
		# Use a different color for boundary cells
		var line_color = grid_color
		if is_boundary_cell(x, y):
			line_color = Color(1.0, 0.0, 0.0, 0.8)  # Bright red for boundary
		
		# Draw all 4 sides of the cell
		# Top line
		draw_line(rect_pos, rect_pos + Vector2(cell_size.x, 0), line_color, 2.0 if is_boundary_cell(x, y) else 1.0)
		# Bottom line
		draw_line(rect_pos + Vector2(0, cell_size.y), rect_pos + cell_size, line_color, 2.0 if is_boundary_cell(x, y) else 1.0)
		# Left line
		draw_line(rect_pos, rect_pos + Vector2(0, cell_size.y), line_color, 2.0 if is_boundary_cell(x, y) else 1.0)
		# Right line
		draw_line(rect_pos + Vector2(cell_size.x, 0), rect_pos + cell_size, line_color, 2.0 if is_boundary_cell(x, y) else 1.0)
		
		# Draw cell coordinates
		var cell_center = Vector2(
			x * cell_size.x + cell_size.x / 2.0,
			y * cell_size.y + cell_size.y / 2.0
		)
		
		# Draw the coordinates centered in the cell
		var coord_text = "(%d,%d)" % [x, y]
		
		# Calculate the string width to center it horizontally
		var text_size = ThemeDB.fallback_font.get_string_size(coord_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		
		# Center the coordinates
		var coord_pos = cell_center - Vector2(text_size.x / 2.0, font_size / 2.0 - 5)
		
		# Draw coordinate text with outline
		draw_string_outline(
			ThemeDB.fallback_font,
			coord_pos,
			coord_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			2,
			Color.BLACK
		)
		draw_string(
			ThemeDB.fallback_font,
			coord_pos,
			coord_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color.WHITE
		)

# The existing process and other methods remain the same as in the original script
