extends Node

# Asteroid generation parameters
@export var asteroid_percentage = 15  # Percentage of grid cells that will contain asteroids
@export var minimum_asteroids = 8     # Minimum number of asteroid fields to generate
@export var min_asteroids_per_cell = 1  # Minimum asteroids per cell
@export var max_asteroids_per_cell = 5  # Maximum asteroids per cell
@export var asteroid_base_size = 0.2    # Base size as fraction of cell size

# Reference to the grid
var grid = null

# Array to track asteroids
var asteroid_fields = []  # Stores positions of asteroid fields
var asteroid_data = []    # Stores additional data like count, sizes, etc.

# Called when the node enters the scene tree for the first time
func _ready():
	grid = get_node_or_null("/root/Main/Grid")
	if not grid:
		push_error("ERROR: Grid not found for asteroid spawning!")
		return
	
	# Connect to grid seed change signal if available
	if grid.has_signal("seed_changed"):
		grid.connect("seed_changed", _on_grid_seed_changed)
	
	print("Asteroid spawner initialized")

# Function to generate asteroids in grid cells
func generate_asteroids():
	# Clear existing asteroid data
	asteroid_fields.clear()
	asteroid_data.clear()
	
	# Make sure grid is ready
	if grid.cell_contents.size() == 0:
		print("ERROR: Grid content arrays not initialized yet")
		return
	
	print("Generating asteroids with seed: ", grid.seed_value)
	
	# Get a list of non-boundary cells that don't already contain planets
	var available_cells = []
	for y in range(1, int(grid.grid_size.y) - 1):
		for x in range(1, int(grid.grid_size.x) - 1):
			# Skip boundary cells
			if grid.is_boundary_cell(x, y):
				continue
			
			# Skip if already has content
			if grid.cell_contents[y][x] != grid.CellContent.EMPTY:
				continue
			
			# Add valid cells
			available_cells.append(Vector2i(x, y))
	
	# Determine how many asteroid fields to spawn
	var non_boundary_count = available_cells.size()
	var asteroid_count = max(minimum_asteroids, int(non_boundary_count * asteroid_percentage / 100.0))
	asteroid_count = min(asteroid_count, non_boundary_count)  # Cap at available cells
	
	print("Found ", non_boundary_count, " available cells - Spawning ", asteroid_count, " asteroid fields")
	
	# Setup RNG with the grid's seed
	var rng = RandomNumberGenerator.new()
	rng.seed = grid.seed_value + 1000  # Add offset to get different pattern from planets
	
	var actual_asteroid_count = 0
	
	# Try multiple times to ensure we get enough asteroid fields
	for i in range(asteroid_count * 2):
		if available_cells.size() == 0:
			break  # No more available cells
		
		# Choose a random available cell
		var idx = rng.randi() % available_cells.size()
		var asteroid_pos = available_cells[idx]
		var x = asteroid_pos.x
		var y = asteroid_pos.y
		
		# Remove this cell from available cells
		available_cells.remove_at(idx)
		
		# Set cell as asteroid in the grid
		grid.cell_contents[y][x] = grid.CellContent.ASTEROID
		actual_asteroid_count += 1
		
		# Generate random number of asteroids for this cell
		var num_asteroids = rng.randi_range(min_asteroids_per_cell, max_asteroids_per_cell)
		grid.asteroid_counts[y][x] = num_asteroids
		
		# Store asteroid field position and data
		var world_pos = Vector2(
			x * grid.cell_size.x + grid.cell_size.x / 2,
			y * grid.cell_size.y + grid.cell_size.y / 2
		)
		
		asteroid_fields.append({
			"position": world_pos,
			"grid_x": x,
			"grid_y": y
		})
		
		# Store asteroid details for each asteroid in the field
		var field_asteroids = []
		for j in range(num_asteroids):
			# Generate a unique seed for each asteroid
			var asteroid_seed = grid.seed_value + y * 1000 + x + j
			var asteroid_rng = RandomNumberGenerator.new()
			asteroid_rng.seed = asteroid_seed
			
			# Size variation
			var size_variation = asteroid_rng.randf_range(0.8, 1.2)
			
			# Random position within the cell
			var pos_offset = Vector2(
				asteroid_rng.randf_range(-grid.cell_size.x * 0.25, grid.cell_size.x * 0.25),
				asteroid_rng.randf_range(-grid.cell_size.y * 0.25, grid.cell_size.y * 0.25)
			)
			
			field_asteroids.append({
				"size": asteroid_base_size * size_variation,
				"offset": pos_offset,
				"color": Color(0.7, 0.3, 0),  # Base asteroid color
				"seed": asteroid_seed
			})
		
		asteroid_data.append({
			"count": num_asteroids,
			"asteroids": field_asteroids
		})
		
		# Stop if we've placed enough asteroid fields
		if actual_asteroid_count >= asteroid_count:
			break
	
	print("Asteroid generation complete - Total asteroid fields: ", actual_asteroid_count)
	
	# Force grid redraw
	grid.queue_redraw()

# Function to reset asteroids (used when seed changes)
func reset_asteroids():
	call_deferred("generate_asteroids")

# Handler for grid seed change
func _on_grid_seed_changed(new_seed = null):
	print("Asteroid spawner detected seed change, regenerating asteroid fields")
	call_deferred("generate_asteroids")
