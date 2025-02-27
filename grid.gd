extends Node2D

# Grid properties
@export var cell_size: Vector2 = Vector2(64, 64)  # Size of each grid cell
@export var grid_size: Vector2 = Vector2(20, 20)  # Number of cells in grid
@export var grid_color: Color = Color(0.2, 0.2, 0.2, 0.5)  # Grid line color
@export var font_size: int = 12
@export var seed_value: int = 0  # Seed for randomization, exposed in inspector
# Chunk load radius is fixed at 1 to ensure only 9 cells maximum
var chunk_load_radius: int = 1  # This is no longer exported to prevent changing it

# Add signal for seed changes
signal seed_changed(new_seed)

# Cell content types
enum CellContent { EMPTY, PLANET, ASTEROID }

# 2D array to store cell contents
var cell_contents = []

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

# New property to track if a boundary warning is currently active
var boundary_warning_active = false

# References to spawners
var planet_spawner = null
var asteroid_spawner = null

func _ready():
	# Get references to spawners
	planet_spawner = get_node_or_null("/root/Main/PlanetSpawner")
	asteroid_spawner = get_node_or_null("/root/Main/AsteroidSpawner")
	
	# Initialize the cell contents based on the seed
	generate_cell_contents()

# New process function to check player position
func _process(delta):
	var player = get_node_or_null("/root/Main/Player")
	if player:
		# Calculate player cell coordinates consistently for all directions
		var player_pos = player.global_position
		var cell_x = int(floor(player_pos.x / cell_size.x))
		var cell_y = int(floor(player_pos.y / cell_size.y))
		
		# Get grid size as integers
		var grid_x = int(grid_size.x)
		var grid_y = int(grid_size.y)
		
		# Explicitly check all boundaries
		var outside_grid = cell_x < 0 or cell_x > grid_x - 1 or cell_y < 0 or cell_y > grid_y - 1
		
		# Store the last valid position when player is inside grid bounds
		if not outside_grid and not player_immobilized:
			last_valid_position = player.global_position
		
		# Handle player leaving the grid entirely
		if outside_grid:
			# Hard stop - force player back to last valid position
			player.global_position = last_valid_position
			
			if not was_outside_grid:
				var main = get_tree().current_scene
				if main.has_method("show_message"):
					main.show_message("You abandoned all logic and were lost in space!")
				
				print("CRITICAL: Player left the grid at position: ", player_pos, " Cell: (", cell_x, ",", cell_y, ")")
				player_immobilized = true
				respawn_timer = 5.0  # 5 seconds until respawn
				
				# Disable player movement
				if player.has_method("set_immobilized"):
					player.set_immobilized(true)
				else:
					player.movement_speed = 0
		
		# Handle respawn timer
		if player_immobilized:
			# Force player to stay at last valid position
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
		# and not already showing a warning
		if is_in_boundary and not was_in_boundary_cell and not boundary_warning_active:
			var main = get_tree().current_scene
			if main.has_method("show_message"):
				main.show_message("WARNING: You are leaving known space!")
				boundary_warning_active = true
		
		# Hide warning when leaving boundary
		if not is_in_boundary and was_in_boundary_cell:
			var main = get_tree().current_scene
			if main.has_method("hide_message"):
				main.hide_message()
				boundary_warning_active = false
		
		# Update boundary tracking
		was_in_boundary_cell = is_in_boundary

	# Force an immediate visual update
	queue_redraw()
	
	# Update enemy visibility based on newly loaded chunks
	update_enemy_visibility()

# Function to update loaded chunks based on player position
func update_loaded_chunks(center_x, center_y):
	# Update player cell tracking
	current_player_cell_x = center_x
	current_player_cell_y = center_y
	
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
	# Only draw grid lines and cell coordinates for the loaded chunks
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
		
		# Draw cell coordinates
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
			var outline_width = 1
			
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
	
	# Delegate rendering to specialized spawners
	if planet_spawner:
		planet_spawner.draw_planets(self, loaded_cells)
	
	if asteroid_spawner:
		asteroid_spawner.draw_asteroids(self, loaded_cells)

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
	regenerate()
	
	# Notify other systems that the seed has changed
	emit_signal("seed_changed", new_seed)

# Initialize the cell contents based on the seed
func generate_cell_contents():
	print("Generating grid with seed: ", seed_value)
	
	# Initialize cell_contents as a 2D array of empty cells
	cell_contents = []
	
	for y in range(int(grid_size.y)):
		cell_contents.append([])
		for x in range(int(grid_size.x)):
			# Default to empty
			cell_contents[y].append(CellContent.EMPTY)
	
	# Initialize loaded cells dictionary
	loaded_cells = {}
	
	print("Grid initialized: ", grid_size.x, "x", grid_size.y, " cells")
	
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
