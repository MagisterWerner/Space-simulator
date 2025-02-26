extends Node2D

# Grid properties
@export var cell_size: Vector2 = Vector2(64, 64)  # Size of each grid cell
@export var grid_size: Vector2 = Vector2(20, 20)  # Number of cells in grid
@export var grid_color: Color = Color(0.2, 0.2, 0.2, 0.5)  # Grid line color
@export var font_size: int = 12
@export var seed_value: int = 0  # Seed for randomization, exposed in inspector

# Chunk load radius is fixed at 1 to ensure only 9 cells maximum
var chunk_load_radius: int = 1  # This is no longer exported to prevent changing it

# Debug mode toggle
var debug_mode: bool = false

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
var previous_loaded_cells = {}

<<<<<<< HEAD
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
	previous_loaded_cells.clear()
	queue_redraw()
	
	print("Grid initialized with size: ", grid_size, " and cell size: ", cell_size)
=======
# New process function to check player position
func _process(delta):
	var player = get_node_or_null("/root/Main/Player")
	if player:
		# Fix for left/up movement: Use floor division to handle negative coordinates correctly
		var cell_x = int(floor(player.global_position.x / cell_size.x))
		var cell_y = int(floor(player.global_position.y / cell_size.y))
		
		# Check if player is outside the grid
		var outside_grid = not is_valid_position(cell_x, cell_y)
		
		# Store the last valid position when player is inside the grid
		if not outside_grid and not player_immobilized:
			last_valid_position = player.global_position
		
		# Handle player leaving the grid entirely
		if outside_grid:
			# Hard stop: don't allow player to move beyond the boundary
			player.global_position = last_valid_position
			
			if not was_outside_grid:
				var main = get_tree().current_scene
				if main.has_method("show_message"):
					main.show_message("You abandoned all logic and were lost in space!")
				
				print("CRITICAL: Player left the grid entirely!")
				player_immobilized = true
				respawn_timer = 5.0  # 5 seconds until respawn
				
				# Find the player's script and disable movement
				if player.has_method("set_immobilized"):
					player.set_immobilized(true)
				else:
					# Add to player GDScript
					player.movement_speed = 0
		
		# Handle respawn timer
		if player_immobilized:
			# Additional safety check - ensure player cannot move
			if player.global_position != last_valid_position:
				player.global_position = last_valid_position
				
			respawn_timer -= delta
			if respawn_timer <= 0:
				player_immobilized = false
				respawn_timer = 0.0
				
				# Re-enable player movement
				if player.has_method("set_immobilized"):
					player.set_immobilized(false)
				else:
					# Reset player speed
					player.movement_speed = 300
				
				# Respawn at initial planet
				var main = get_tree().current_scene
				if main.has_method("respawn_player_at_initial_planet"):
					main.respawn_player_at_initial_planet()
				
				# Reset the tracking variables after respawn
				was_outside_grid = false
				was_in_boundary_cell = false
				return
		
		# Update outside grid tracking
		was_outside_grid = outside_grid
		
		# Skip boundary checks if we're outside the grid
		if outside_grid:
			return
		
		# Check if player is in a boundary cell
		var is_in_boundary = is_boundary_cell(cell_x, cell_y)
		
		# Show warning message only when first entering a boundary cell
		if is_in_boundary and not was_in_boundary_cell:
			print("WARNING: You are leaving known space!")
			var main = get_tree().current_scene
			if main.has_method("show_message"):
				main.show_message("WARNING: You are leaving known space!")
		
		# Update boundary status
		was_in_boundary_cell = is_in_boundary
		
		# Only update if player moved to a new cell
		if cell_x != current_player_cell_x or cell_y != current_player_cell_y:
			current_player_cell_x = cell_x
			current_player_cell_y = cell_y
			update_loaded_chunks(cell_x, cell_y)
			queue_redraw()
>>>>>>> parent of 3cca589 (Huge enemy update)

# Check if a position is valid (within bounds)
func is_valid_position(x, y):
	return x >= 0 and x < grid_size.x and y >= 0 and y < grid_size.y

# Enhanced mark_cell_occupied method
func mark_cell_occupied(x, y, content_type):
	if not is_valid_position(x, y):
		return false
	
	# Create Vector2 key once
	var cell_key = Vector2(x, y)
	
	# Get current cell content
	var current_content = get_cell_content(x, y)
	
	# Prevent mixing of different content types
	if current_content != CellContent.EMPTY:
		# If trying to add a different type to an already occupied cell
		if current_content != content_type:
			print("Warning: Cannot occupy cell (%d,%d) - already occupied with type %d" % [x, y, current_content])
			return false
	
	# Update cell contents array
	if y < cell_contents.size() and x < cell_contents[y].size():
		cell_contents[y][x] = content_type
		occupied_cells[cell_key] = content_type
		print("Cell (%d,%d) marked as occupied with content type: %d" % [x, y, content_type])
		return true
	
	return false

# Check if a cell is already occupied
func is_cell_occupied(x, y):
	if not is_valid_position(x, y):
		return true
	
	return get_cell_content(x, y) != CellContent.EMPTY

# Clear cell occupancy (useful when regenerating grid)
func clear_cell_occupancy():
	print("Clearing all cell occupancy data")
	occupied_cells.clear()
	# Reinitialize cell contents array with EMPTY
	for y in range(int(grid_size.y)):
		for x in range(int(grid_size.x)):
			if y < cell_contents.size() and x < cell_contents[y].size():
				cell_contents[y][x] = CellContent.EMPTY

# Check if a cell is on the boundary (outermost edge)
func is_boundary_cell(x, y):
	return x == 0 or y == 0 or x == grid_size.x - 1 or y == grid_size.y - 1

# Modified set_cell_content to enforce occupancy rules
func set_cell_content(x, y, content_type):
	if not is_valid_position(x, y):
		return false
	
<<<<<<< HEAD
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

# Enhanced update_loaded_chunks function to better track changes
func update_loaded_chunks(center_x, center_y):
	print("Updating loaded chunks at center: (", center_x, ",", center_y, ")")
	
	# Force update even if the center hasn't changed, for initial loading
	var force_update = (loaded_cells.size() == 0)
	
	# Check if center position has changed
	if not force_update and center_x == current_player_cell_x and center_y == current_player_cell_y:
		print("Cell center hasn't changed, skipping update")
		return false  # No need to update
	
	# Store current loaded cells to check for changes
	previous_loaded_cells = loaded_cells.duplicate()
	loaded_cells.clear()
	
	# Calculate new loaded cells (fixed radius of 1)
	for y in range(center_y - chunk_load_radius, center_y + chunk_load_radius + 1):
		for x in range(center_x - chunk_load_radius, center_x + chunk_load_radius + 1):
			if is_valid_position(x, y):
				loaded_cells[Vector2(x, y)] = true
				print("Added loaded cell: (", x, ",", y, ")")
	
	# Update cached player position
	current_player_cell_x = center_x
	current_player_cell_y = center_y
	
	print("Total loaded cells after update: ", loaded_cells.size())
	
	# Check if cells have actually changed
	var has_changes = force_update
	if not has_changes and previous_loaded_cells.size() != loaded_cells.size():
		has_changes = true
	else:
		for cell in loaded_cells.keys():
			if not previous_loaded_cells.has(cell):
				has_changes = true
				break
	
	if has_changes or force_update:
		# Force an immediate visual update
		print("Cells changed, updating visualization")
		queue_redraw()
		
		# Emit signal for other nodes to update visibility
		emit_signal("chunks_updated", loaded_cells)
		print("Loaded cells updated. Center: (", center_x, ",", center_y, ") - Total loaded: ", loaded_cells.size())
		return true
	
	print("No changes in loaded cells")
	return false

# Draw grid in loaded chunks with enhanced debug visualization
=======
	# If no planet was found in the 1-cell radius, we can place a planet here
	return true

# Generate cell contents based on the seed
func generate_cell_contents():
	# Create a new random number generator
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# Recreate the arrays from scratch
	cell_contents = []
	asteroid_counts = []
	planet_sizes = []
	planet_colors = []
	for y in range(int(grid_size.y)):
		var content_row = []
		var count_row = []
		var size_row = []
		var color_row = []
		for x in range(int(grid_size.x)):
			content_row.append(CellContent.EMPTY)
			count_row.append(0)
			size_row.append(0.0)
			color_row.append(Color.WHITE)
		cell_contents.append(content_row)
		asteroid_counts.append(count_row)
		planet_sizes.append(size_row)
		planet_colors.append(color_row)
	
	# Second pass: Place objects
	var planet_count = 0
	for y in range(int(grid_size.y)):
		for x in range(int(grid_size.x)):
			# Skip boundary cells - they must always remain empty
			if is_boundary_cell(x, y):
				continue
				
			var rand_value = rng.randi() % 100
			
			if rand_value < 30:
				if rand_value < 15:
					if can_place_planet(x, y):
						cell_contents[y][x] = CellContent.PLANET
						planet_count += 1
						# Generate planet size and color
						var size_rng = RandomNumberGenerator.new()
						size_rng.seed = seed_value + y * 1000 + x
						planet_sizes[y][x] = size_rng.randf_range(0.3, 0.5)  # Random size between 30% and 50% of cell size
						var color_rng = RandomNumberGenerator.new()
						color_rng.seed = seed_value + y * 1000 + x
						planet_colors[y][x] = planet_color_palette[color_rng.randi() % planet_color_palette.size()]
					else:
						if rng.randi() % 100 < 50:
							cell_contents[y][x] = CellContent.ASTEROID
							# Generate asteroid count
							var count_rng = RandomNumberGenerator.new()
							count_rng.seed = seed_value + y * 1000 + x
							asteroid_counts[y][x] = count_rng.randi() % 3 + 1
				else:
					cell_contents[y][x] = CellContent.ASTEROID
					# Generate asteroid count
					var count_rng = RandomNumberGenerator.new()
					count_rng.seed = seed_value + y * 1000 + x
					asteroid_counts[y][x] = count_rng.randi() % 3 + 1
	
	# Debug: Print planet count to verify planets are being created
	print("Generated grid with seed: ", seed_value, " - Total planets created: ", planet_count)
	
	# If no planets were generated, force at least one planet
	if planet_count == 0:
		print("No planets generated! Forcing a planet at position (5,5)")
		if is_valid_position(5, 5):
			cell_contents[5][5] = CellContent.PLANET
			var size_rng = RandomNumberGenerator.new()
			size_rng.seed = seed_value + 5000 + 5
			planet_sizes[5][5] = size_rng.randf_range(0.3, 0.5)
			planet_colors[5][5] = planet_color_palette[0]
			queue_redraw()
	
	# Reset loaded chunks and force redraw
	loaded_cells.clear()
	queue_redraw()

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
	
	print("Loaded cells updated. Center: (", center_x, ",", center_y, ") - Total loaded: ", loaded_cells.size())

>>>>>>> parent of 3cca589 (Huge enemy update)
func _draw():
	print("Drawing grid with loaded cells count: ", loaded_cells.size())
	
	# Handle the case where there are no loaded cells (should not happen)
	if loaded_cells.size() == 0:
		# Emergency: force loading of the center cells
		print("WARNING: No loaded cells found during drawing! Loading center cells.")
		for y in range(int(grid_size.y/2) - 1, int(grid_size.y/2) + 2):
			for x in range(int(grid_size.x/2) - 1, int(grid_size.x/2) + 2):
				if is_valid_position(x, y):
					loaded_cells[Vector2(x, y)] = true
					print("Emergency loaded cell: (", x, ",", y, ")")
	
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
		
		# Debug visualization of cell contents when debug mode is enabled
		if debug_mode:
			var content = get_cell_content(x, y)
			
			# Choose color based on content
			var fill_color
			match content:
				CellContent.EMPTY: fill_color = Color(0, 1, 0, 0.1)  # Green
				CellContent.PLANET: fill_color = Color(0, 0, 1, 0.2)  # Blue
				CellContent.ASTEROID: fill_color = Color(1, 0, 0, 0.2)  # Red
				CellContent.PLANET_AND_ASTEROID: fill_color = Color(1, 0, 1, 0.3)  # Purple
			
			# Draw cell overlay
			draw_rect(Rect2(rect_pos, cell_size), fill_color)
			
			# Draw cell content status text
			var content_text = "Empty"
			if content == CellContent.PLANET:
				content_text = "Planet"
			elif content == CellContent.ASTEROID:
				content_text = "Asteroid"
			elif content == CellContent.PLANET_AND_ASTEROID:
				content_text = "Both"
			
			# Draw content text below coordinates
			var content_pos = Vector2(
				cell_center.x - 20,
				cell_center.y + 15
			)
			draw_string(
				ThemeDB.fallback_font,
				content_pos,
				content_text,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				font_size - 2,
				Color.WHITE
			)
