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
			# Only show warning message from one place (removed duplicate message)
			var main = get_tree().current_scene
			if main.has_method("show_message"):
				main.show_message("WARNING: You are leaving known space!")

	# Force an immediate visual update
	queue_redraw()
	
	# Update enemy visibility based on newly loaded chunks
	update_enemy_visibility()

# Function to update loaded chunks based on player position
func update_loaded_chunks(center_x, center_y):
	# Update player cell tracking
	current_player_cell_x = center_x
	current_player_cell_y = center_y
	
	# Update tracking for boundary cells
	if is_boundary_cell(center_x, center_y):
		was_in_boundary_cell = true
	else:
		was_in_boundary_cell = false
	
	# Clear existing loaded cells
	loaded_cells.clear()
	
	# Add cells within the chunk load radius to the loaded cells dictionary
	for y in range(center_y - chunk_load_radius, center_y + chunk_load_radius + 1):
		for x in range(center_x - chunk_load_radius, center_x + chunk_load_radius + 1):
			# Only add valid positions
			if is_valid_position(x, y):
				loaded_cells[Vector2i(x, y)] = true
	
	print("Loaded cells updated. Center: (", center_x, ",", center_y, ") - Total loaded: ", loaded_cells.size())

# Function to update enemy visibility based on loaded chunks
func update_enemy_visibility():
	# Get a reference to the enemy spawner
	var enemy_spawner = get_node_or_null("/root/Main/EnemySpawner")
	if not enemy_spawner:
		return
		
	# Update visibility for each enemy based on whether its cell is loaded
	for enemy in enemy_spawner.spawned_enemies:
		if is_instance_valid(enemy):
			var enemy_cell_x = int(floor(enemy.global_position.x / cell_size.x))
			var enemy_cell_y = int(floor(enemy.global_position.y / cell_size.y))
			
			# Check if the enemy's cell is currently loaded
			var is_cell_loaded = loaded_cells.has(Vector2i(enemy_cell_x, enemy_cell_y))
			
			# Set the enemy's active state
			enemy.update_active_state(is_cell_loaded)

func _draw():
	# Only draw grid lines for the loaded chunks
	for cell_pos in loaded_cells.keys():
		var x = int(cell_pos.x)
		var y = int(cell_pos.y)
		
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
			
			# Draw text with outline via multiple offset strings
			var outline_color = Color.BLACK
			var outline_width = 2
			
			for dx in range(-outline_width, outline_width + 1):
				for dy in range(-outline_width, outline_width + 1):
					if dx != 0 or dy != 0:  # Skip center position
						draw_string(
							ThemeDB.fallback_font,
							coord_pos + Vector2(dx, dy),
							coord_text,
							HORIZONTAL_ALIGNMENT_LEFT,
							-1,
							font_size,
							outline_color
						)
			
			# Draw main text
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

# Initialize the cell contents based on the seed
func generate_cell_contents():
	print("Generating grid with seed: ", seed_value)
	
	# Initialize the RNG with the seed
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# Initialize cell_contents as a 2D array of empty cells
	cell_contents = []
	asteroid_counts = []
	planet_sizes = []
	planet_colors = []
	
	for y in range(int(grid_size.y)):
		cell_contents.append([])
		asteroid_counts.append([])
		planet_sizes.append([])
		planet_colors.append([])
		
		for x in range(int(grid_size.x)):
			# Default to empty
			cell_contents[y].append(CellContent.EMPTY)
			asteroid_counts[y].append(0)
			planet_sizes[y].append(0.0)
			planet_colors[y].append(Color.WHITE)
	
	# Create a set to track reserved cells (cells that cannot have planets)
	var reserved_cells = {}
	
	# Generate planets (about 10% of non-boundary cells)
	var non_boundary_count = (grid_size.x - 2) * (grid_size.y - 2)
	var planet_count = int(non_boundary_count * 0.1)
	var actual_planet_count = 0
	
	for i in range(planet_count * 3):  # Try more times to ensure we get enough planets
		# Choose a random non-boundary cell
		var x = rng.randi_range(1, grid_size.x - 2)
		var y = rng.randi_range(1, grid_size.y - 2)
		
		# Skip if this cell or adjacent cells are reserved
		if reserved_cells.has(Vector2i(x, y)):
			continue
		
		# Set as planet
		cell_contents[y][x] = CellContent.PLANET
		actual_planet_count += 1
		
		# Generate random size (0.2 to 0.4 of cell size)
		planet_sizes[y][x] = rng.randf_range(0.25, 0.4)
		
		# Choose a random color from the palette
		var color_index = rng.randi() % planet_color_palette.size()
		planet_colors[y][x] = planet_color_palette[color_index]
		
		# Reserve this cell and all cells within 2 cells distance (including diagonals)
		for dy in range(-2, 3):  # -2, -1, 0, 1, 2
			for dx in range(-2, 3):  # -2, -1, 0, 1, 2
				var nx = x + dx
				var ny = y + dy
				
				# Only reserve valid positions
				if is_valid_position(nx, ny):
					reserved_cells[Vector2i(nx, ny)] = true
		
		# Stop if we've placed enough planets
		if actual_planet_count >= planet_count:
			break
	
	# Generate asteroids (about 15% of non-boundary cells)
	var asteroid_count = int(non_boundary_count * 0.15)
	var actual_asteroid_count = 0
	
	for i in range(asteroid_count * 2):  # Try more times to ensure we get enough asteroids
		# Choose a random non-boundary cell
		var x = rng.randi_range(1, grid_size.x - 2)
		var y = rng.randi_range(1, grid_size.y - 2)
		
		# Skip if already occupied
		if cell_contents[y][x] != CellContent.EMPTY:
			continue
		
		# Set as asteroid field
		cell_contents[y][x] = CellContent.ASTEROID
		actual_asteroid_count += 1
		
		# Generate random number of asteroids (1 to 5)
		asteroid_counts[y][x] = rng.randi_range(1, 5)
		
		# Stop if we've placed enough asteroids
		if actual_asteroid_count >= asteroid_count:
			break
	
	# Initialize loaded cells dictionary
	loaded_cells = {}
	
	print("Grid generated: ", grid_size.x, "x", grid_size.y, " cells")
	print("Planets: ", actual_planet_count, " - Asteroids: ", actual_asteroid_count)
	
	# Ensure the grid is visually updated
	queue_redraw()

# Check if a position is valid (within grid bounds)
func is_valid_position(x, y):
	return x >= 0 and x < int(grid_size.x) and y >= 0 and y < int(grid_size.y)

# Check if a cell is at the boundary of the grid
func is_boundary_cell(x, y):
	var grid_x = int(grid_size.x)
	var grid_y = int(grid_size.y)
	return (x == 0 or x == grid_x - 1 or y == 0 or y == grid_y - 1) and is_valid_position(x, y)
