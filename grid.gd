extends Node2D

# Grid properties
@export var cell_size: Vector2 = Vector2(64, 64)  # Size of each grid cell
@export var grid_size: Vector2 = Vector2(20, 20)  # Number of cells in grid
@export var grid_color: Color = Color(0.2, 0.2, 0.2, 0.5)  # Grid line color
@export var font_size: int = 12
@export var seed_value: int = 0  # Seed for randomization, exposed in inspector
# Chunk load radius is fixed at 1 to ensure only 9 cells maximum
var chunk_load_radius: int = 1  # This is no longer exported to prevent changing it

# Cell content types
enum CellContent { EMPTY, PLANET, ASTEROID }

# 2D array to store cell contents
var cell_contents = []

# 2D array to store number of asteroids per cell
var asteroid_counts = []

# 2D array to store planet sizes and colors
var planet_sizes = []
var planet_colors = []

# Planet colors
var planet_color_palette = [Color.WHITE, Color.GREEN, Color.RED, Color(0.96, 0.96, 0.86), Color.BLUE]

# Current player cell coordinates
var current_player_cell_x = -1
var current_player_cell_y = -1

# Dictionary to track which cells are currently loaded
var loaded_cells = {}

# Player state tracking
var was_in_boundary_cell = false
var was_outside_grid = false
var player_immobilized = false
var respawn_timer = 0.0
var last_valid_position = Vector2.ZERO

func _ready():
	# Initialize the cell contents based on the seed
	generate_cell_contents()

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

# Check if a position is valid (within bounds)
func is_valid_position(x, y):
	return x >= 0 and x < grid_size.x and y >= 0 and y < grid_size.y

# Check if a cell is on the boundary (outermost edge)
func is_boundary_cell(x, y):
	return x == 0 or y == 0 or x == grid_size.x - 1 or y == grid_size.y - 1

# Check if a planet can be placed at the given position
func can_place_planet(x, y):
	# Check all cells within a 1-cell radius (ensuring at least 1 non-planet cell between planets)
	# This relaxes the spacing requirement to allow more planets to be placed
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			# Skip the center cell (the cell we're checking)
			if dx == 0 and dy == 0:
				continue
				
			# Calculate the adjacent cell position
			var adj_x = x + dx
			var adj_y = y + dy
			
			# Check if the adjacent cell is within bounds and contains a planet
			if is_valid_position(adj_x, adj_y) and cell_contents[adj_y][adj_x] == CellContent.PLANET:
				return false
	
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

func _draw():
	# Only draw grid lines for the loaded chunks
	for cell_pos in loaded_cells.keys():
		var x = cell_pos.x
		var y = cell_pos.y
		
		# Draw cell borders
		var rect_pos = Vector2(x * cell_size.x, y * cell_size.y)
		var rect_size = cell_size
		
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
		
		# Draw cell content for this loaded cell
		if y < cell_contents.size() and x < cell_contents[y].size():
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
			
			# Get the cell content
			var content = cell_contents[y][x]
			
			# Draw cell content if not empty
			if content != CellContent.EMPTY:
				if content == CellContent.PLANET:
					# Draw a circle (planet) with outline
					var shape_size = min(cell_size.x, cell_size.y) * planet_sizes[y][x]
					draw_circle(cell_center, shape_size, planet_colors[y][x])
					draw_arc(cell_center, shape_size, 0, TAU, 32, planet_colors[y][x].darkened(0.2), 2.0, true)  # Outline
					
					# Add some detail to the planet (rings or surface features)
					var ring_radius = shape_size * 0.7
					draw_arc(cell_center, ring_radius, 0, PI, 16, planet_colors[y][x].lightened(0.1), 1.5)
					draw_arc(cell_center, ring_radius, PI, TAU, 16, planet_colors[y][x].lightened(0.1), 1.5)
					
				elif content == CellContent.ASTEROID:
					var num_asteroids = asteroid_counts[y][x]
					var base_shape_size = min(cell_size.x, cell_size.y) * 0.2  # Smaller size for multiple asteroids
					var asteroid_positions = []  # Track positions to avoid overlap
					
					for i in range(num_asteroids):
						var asteroid_rng = RandomNumberGenerator.new()
						asteroid_rng.seed = seed_value + y * 1000 + x + i  # Unique seed per asteroid
						
						# Random position within the cell, ensuring no overlap and respecting cell borders
						var pos_offset = Vector2.ZERO
						var attempts = 0
						var asteroid_pos = Vector2.ZERO
						while attempts < 10:  # Limit attempts to avoid infinite loops
							pos_offset = Vector2(
								asteroid_rng.randf_range(-cell_size.x * 0.25, cell_size.x * 0.25),
								asteroid_rng.randf_range(-cell_size.y * 0.25, cell_size.y * 0.25)
							)
							asteroid_pos = cell_center + pos_offset
							
							# Ensure the asteroid stays within the cell bounds
							var cell_min = Vector2(x * cell_size.x, y * cell_size.y)
							var cell_max = Vector2((x + 1) * cell_size.x, (y + 1) * cell_size.y)
							if asteroid_pos.x - base_shape_size < cell_min.x or asteroid_pos.x + base_shape_size > cell_max.x:
								continue
							if asteroid_pos.y - base_shape_size < cell_min.y or asteroid_pos.y + base_shape_size > cell_max.y:
								continue
							
							# Check for overlap with other asteroids in the same cell
							var overlap = false
							for pos in asteroid_positions:
								if pos.distance_to(asteroid_pos) < base_shape_size * 1.5:
									overlap = true
									break
							if not overlap:
								break
							attempts += 1
						
						asteroid_positions.append(cell_center + pos_offset)
						asteroid_pos = cell_center + pos_offset
						
						# Generate triangle points
						var shape_size = base_shape_size * asteroid_rng.randf_range(0.8, 1.2)  # Slight size variation
						var triangle_points = [
							asteroid_pos + Vector2(0, -shape_size),
							asteroid_pos + Vector2(-shape_size * 0.866, shape_size * 0.5),
							asteroid_pos + Vector2(shape_size * 0.866, shape_size * 0.5)
						]
						
						# Perturb points for irregular shape
						for j in triangle_points.size():
							triangle_points[j] += Vector2(
								asteroid_rng.randf_range(-5, 5),
								asteroid_rng.randf_range(-5, 5)
							)
						
						# Draw asteroid
						var triangle_color = Color(0.7, 0.3, 0)
						draw_colored_polygon(triangle_points, triangle_color)
						draw_polyline(triangle_points + [triangle_points[0]], Color(0.9, 0.4, 0), 2.0, true)
						
						# Draw crater
						var crater_pos = asteroid_pos + Vector2(
							asteroid_rng.randf_range(-shape_size * 0.3, shape_size * 0.3),
							asteroid_rng.randf_range(-shape_size * 0.2, shape_size * 0.2)
						)
						draw_circle(crater_pos, shape_size * 0.15, Color(0.6, 0.25, 0))

# Regenerate the grid when properties change
func regenerate():
	generate_cell_contents()

# Update handlers for the inspector values
func _set(property, _value):
	if property == "seed_value" or property == "grid_size":
		call_deferred("regenerate")
	return false

# Add a method to explicitly change the seed from code
func set_seed(new_seed):
	seed_value = new_seed
	print("Setting new seed: ", new_seed)
	
	# Regenerate the grid with new seed
	# (Player will be handled by main.gd)
	regenerate()
