extends Node2D

signal asteroid_field_spawned(position, grid_x, grid_y, count)

# Asteroid spawn parameters
@export var asteroid_probability = 15  # Percentage chance for a cell to have asteroids
@export var asteroid_size_base = 0.2   # Base size relative to cell
@export var asteroid_size_variance = 0.2  # Size variance (±)

# Asteroid appearance
@export var asteroid_color = Color(0.7, 0.3, 0)
@export var asteroid_outline_color = Color(0.9, 0.4, 0)

# Debug mode toggle
var debug_mode: bool = false

# Reference to the grid
var grid = null
# Reference to planet spawner to check for conflicts
var planet_spawner = null

# Dictionary to store asteroid field data
# Key: Vector2(x, y) for grid coords, Value: Dictionary with asteroid field properties
var asteroid_fields = {}

# Tracking for visibility changes
var previously_visible_cells = {}

# Called when the node enters the scene tree
func _ready():
	# Find the grid
	grid = get_node_or_null("/root/Main/Grid")
	if not grid:
		push_error("ERROR: Grid not found for asteroid spawning!")
	
	# Find the planet spawner
	planet_spawner = get_node_or_null("/root/Main/PlanetSpawner")

# Initialize asteroid spawning with specific grid and seed
func initialize(target_grid, seed_val):
	# Update grid reference
	grid = target_grid
	
	# Ensure planet spawner is referenced
	if planet_spawner == null:
		planet_spawner = get_node_or_null("/root/Main/PlanetSpawner")
	
	# Clear existing asteroid fields and visibility tracking
	asteroid_fields.clear()
	previously_visible_cells.clear()
	
	# Generate asteroid fields
	generate_asteroid_fields(seed_val)
	
	print("Asteroid spawner initialized - Total asteroid fields: ", asteroid_fields.size())
	return asteroid_fields.size() > 0

# Enhanced can_place_asteroid_field function with better conflict detection
func can_place_asteroid_field(x, y):
	# Skip if position is invalid
	if not grid.is_valid_position(x, y):
		print("Cannot place asteroid field at (", x, ",", y, ") - Invalid position")
		return false
		
	# Check if the specific cell is already occupied
	if grid.is_cell_occupied(x, y):
		print("Cannot place asteroid field at (", x, ",", y, ") - Cell already occupied")
		return false
	
	# Skip boundary cells - they must always remain empty
	if grid.is_boundary_cell(x, y):
		print("Cannot place asteroid field at (", x, ",", y, ") - Boundary cell")
		return false
	
	# Check all cells within a 1-cell radius for conflicts
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			# Calculate the adjacent cell position
			var adj_x = x + dx
			var adj_y = y + dy
			
			# Skip if out of bounds
			if not grid.is_valid_position(adj_x, adj_y):
				continue
			
			# Prevent asteroid fields from being too close to each other
			if asteroid_fields.has(Vector2(adj_x, adj_y)):
				print("Cannot place asteroid field at (", x, ",", y, ") - Too close to another asteroid field at (", adj_x, ",", adj_y, ")")
				return false
			
			# Prevent asteroid fields near planets
			if planet_spawner and planet_spawner.get_planet_at(adj_x, adj_y) != null:
				print("Cannot place asteroid field at (", x, ",", y, ") - Too close to a planet at (", adj_x, ",", adj_y, ")")
				return false
	
	# If no conflicts were found, we can place an asteroid field here
	return true

# Main asteroid field generation function
func generate_asteroid_fields(seed_val):
	# Create a new random number generator
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val + 12345  # Offset seed for asteroids to be different from planets
	
	# First pass: determine which cells will have asteroid fields
	for y in range(int(grid.grid_size.y)):
		for x in range(int(grid.grid_size.x)):
			var rand_value = rng.randi() % 100
			
			if rand_value < asteroid_probability and can_place_asteroid_field(x, y):
				# Generate asteroid count
				var count_rng = RandomNumberGenerator.new()
				count_rng.seed = seed_val + y * 1000 + x
				var asteroid_count = count_rng.randi() % 3 + 1  # 1-3 asteroids
				
				# Generate positions of individual asteroids within the field
				var asteroid_positions = generate_asteroid_positions(seed_val, x, y, asteroid_count)
				
				# Set up asteroid field data
				var field_data = {
					"position": Vector2(
						x * grid.cell_size.x + grid.cell_size.x / 2,
						y * grid.cell_size.y + grid.cell_size.y / 2
					),
					"count": asteroid_count,
					"grid_x": x,
					"grid_y": y,
					"asteroids": asteroid_positions
				}
				
				# Store asteroid field data in dictionary
				asteroid_fields[Vector2(x, y)] = field_data
				
				# Mark the cell as occupied
				grid.mark_cell_occupied(x, y, grid.CellContent.ASTEROID)
				
				# Signal that an asteroid field was spawned
				emit_signal("asteroid_field_spawned", field_data.position, x, y, asteroid_count)
	
	# Ensure at least one asteroid field exists
	if asteroid_fields.size() == 0:
		_force_spawn_fallback_asteroid_field(seed_val)
	
	print("Generated asteroid fields with seed: ", seed_val, " - Total fields created: ", asteroid_fields.size())

# Force spawn a fallback asteroid field
func _force_spawn_fallback_asteroid_field(seed_val):
	print("No asteroid fields generated! Forcing an asteroid field at fallback position")
	
	# Try position (5,5) and nearby cells first
	var fallback_positions = [
		Vector2(5, 5),
		Vector2(4, 4),
		Vector2(6, 6),
		Vector2(3, 3),
		Vector2(7, 7),
		Vector2(2, 2),
		Vector2(8, 8),
		Vector2(9, 9)
	]
	
	for pos in fallback_positions:
		var x = int(pos.x)
		var y = int(pos.y)
		
		if grid.is_valid_position(x, y) and can_place_asteroid_field(x, y):
			# Generate asteroid count
			var count_rng = RandomNumberGenerator.new()
			count_rng.seed = seed_val + y * 1000 + x
			var asteroid_count = count_rng.randi() % 3 + 1  # 1-3 asteroids
			
			# Generate positions of individual asteroids within the field
			var asteroid_positions = generate_asteroid_positions(seed_val, x, y, asteroid_count)
			
			# Set up asteroid field data
			var field_data = {
				"position": Vector2(
					x * grid.cell_size.x + grid.cell_size.x / 2,
					y * grid.cell_size.y + grid.cell_size.y / 2
				),
				"count": asteroid_count,
				"grid_x": x,
				"grid_y": y,
				"asteroids": asteroid_positions
			}
			
			# Store asteroid field data in dictionary
			asteroid_fields[Vector2(x, y)] = field_data
			
			# Mark the cell as occupied
			grid.mark_cell_occupied(x, y, grid.CellContent.ASTEROID)
			
			# Signal that an asteroid field was spawned
			emit_signal("asteroid_field_spawned", field_data.position, x, y, asteroid_count)
			
			print("Forced asteroid field creation at position: (", x, ",", y, ")")
			return
	
	# If all predetermined positions failed, try emergency placement
	_emergency_asteroid_placement(seed_val)

# Emergency asteroid placement with less strict rules
func _emergency_asteroid_placement(seed_val):
	print("EMERGENCY: Attempting asteroid field placement with reduced restrictions")
	
	# Try placing an asteroid field anywhere that's not the boundary and not occupied
	for y in range(1, int(grid.grid_size.y) - 1):
		for x in range(1, int(grid.grid_size.x) - 1):
			if not grid.is_cell_occupied(x, y):
				# Generate asteroid count
				var count_rng = RandomNumberGenerator.new()
				count_rng.seed = seed_val + y * 1000 + x
				var asteroid_count = 1  # Just one asteroid in emergency mode
				
				# Generate positions of individual asteroids within the field
				var asteroid_positions = generate_asteroid_positions(seed_val, x, y, asteroid_count)
				
				# Set up asteroid field data
				var field_data = {
					"position": Vector2(
						x * grid.cell_size.x + grid.cell_size.x / 2,
						y * grid.cell_size.y + grid.cell_size.y / 2
					),
					"count": asteroid_count,
					"grid_x": x,
					"grid_y": y,
					"asteroids": asteroid_positions
				}
				
				# Store asteroid field data in dictionary
				asteroid_fields[Vector2(x, y)] = field_data
				
				# Mark the cell as occupied
				if not grid.mark_cell_occupied(x, y, grid.CellContent.ASTEROID):
					push_error("Failed to mark cell as occupied in emergency asteroid placement")
				
				# Signal that an asteroid field was spawned
				emit_signal("asteroid_field_spawned", field_data.position, x, y, asteroid_count)
				
				print("EMERGENCY: Forced asteroid field creation at position: (", x, ",", y, ")")
				return

# Generate positions for individual asteroids within a field
func generate_asteroid_positions(seed_val, grid_x, grid_y, count):
	var positions = []
	var base_shape_size = min(grid.cell_size.x, grid.cell_size.y) * asteroid_size_base
	var cell_center = Vector2(
		grid_x * grid.cell_size.x + grid.cell_size.x / 2,
		grid_y * grid.cell_size.y + grid.cell_size.y / 2
	)
	
	var asteroid_rng = RandomNumberGenerator.new()
	asteroid_rng.seed = seed_val + grid_y * 1000 + grid_x
	
	for i in range(count):
		var attempts = 0
		var asteroid_data = null
		
		while attempts < 10 and asteroid_data == null:  # Limit attempts to avoid infinite loops
			var pos_offset = Vector2(
				asteroid_rng.randf_range(-grid.cell_size.x * 0.25, grid.cell_size.x * 0.25),
				asteroid_rng.randf_range(-grid.cell_size.y * 0.25, grid.cell_size.y * 0.25)
			)
			var asteroid_pos = cell_center + pos_offset
			
			# Ensure the asteroid stays within the cell bounds
			var cell_min = Vector2(grid_x * grid.cell_size.x, grid_y * grid.cell_size.y)
			var cell_max = Vector2((grid_x + 1) * grid.cell_size.x, (grid_y + 1) * grid.cell_size.y)
			if asteroid_pos.x - base_shape_size < cell_min.x or asteroid_pos.x + base_shape_size > cell_max.x:
				attempts += 1
				continue
			if asteroid_pos.y - base_shape_size < cell_min.y or asteroid_pos.y + base_shape_size > cell_max.y:
				attempts += 1
				continue
			
			# Check for overlap with other asteroids in the same cell
			var overlap = false
			for existing in positions:
				if existing.position.distance_to(asteroid_pos) < base_shape_size * 1.5:
					overlap = true
					break
			
			if overlap:
				attempts += 1
				continue
			
			# Generate size with some variance
			var size = base_shape_size * asteroid_rng.randf_range(1.0 - asteroid_size_variance, 1.0 + asteroid_size_variance)
			
			# Generate triangle points for asteroid shape
			var triangle_points = [
				asteroid_pos + Vector2(0, -size),
				asteroid_pos + Vector2(-size * 0.866, size * 0.5),
				asteroid_pos + Vector2(size * 0.866, size * 0.5)
			]
			
			# Perturb points for irregular shape
			for j in triangle_points.size():
				triangle_points[j] += Vector2(
					asteroid_rng.randf_range(-5, 5),
					asteroid_rng.randf_range(-5, 5)
				)
			
			# Generate crater position
			var crater_pos = asteroid_pos + Vector2(
				asteroid_rng.randf_range(-size * 0.3, size * 0.3),
				asteroid_rng.randf_range(-size * 0.2, size * 0.2)
			)
			
			asteroid_data = {
				"position": asteroid_pos,
				"size": size,
				"points": triangle_points,
				"crater_pos": crater_pos,
				"crater_size": size * 0.15
			}
			
			positions.append(asteroid_data)
		
		# If we exhausted attempts, just skip this asteroid
		if attempts >= 10 and asteroid_data == null:
			print("Warning: Could not place asteroid after multiple attempts")
	
	return positions

# Get all asteroid fields for external use
func get_all_asteroid_fields():
	var field_list = []
	
	for coord in asteroid_fields.keys():
		field_list.append(asteroid_fields[coord])
	
	return field_list

# Get a specific asteroid field at grid coordinates
func get_asteroid_field_at(grid_x, grid_y):
	var coord = Vector2(grid_x, grid_y)
	if asteroid_fields.has(coord):
		return asteroid_fields[coord]
	return null

# Enhanced update_visibility function to track visibility changes
func update_visibility():
	# Skip if no grid or no asteroid fields
	if not grid or asteroid_fields.is_empty():
		queue_redraw()
		return
	
	# Track which cells are now visible
	var currently_visible_cells = {}
	
	# Check which asteroid fields are in loaded chunks
	for coord in asteroid_fields.keys():
		if grid.loaded_cells.has(coord):
			currently_visible_cells[coord] = true
	
	# Check if visibility has changed
	var visibility_changed = false
	
	# Check if any asteroid fields became visible
	for coord in currently_visible_cells.keys():
		if not previously_visible_cells.has(coord):
			visibility_changed = true
			break
			
	# Check if any asteroid fields became invisible
	if not visibility_changed:
		for coord in previously_visible_cells.keys():
			if not currently_visible_cells.has(coord):
				visibility_changed = true
				break
	
	# Update tracking and redraw if needed
	if visibility_changed:
		previously_visible_cells = currently_visible_cells.duplicate()
		print("Asteroid field visibility changed - redrawing")
		queue_redraw()
	elif debug_mode:
		# Always redraw in debug mode to update debug visualization
		queue_redraw()

# Enhanced draw function with debug visualization
func _draw():
	if not grid or asteroid_fields.is_empty():
		return
	
	for coord in asteroid_fields.keys():
		# Only draw asteroids in loaded chunks
		if grid.loaded_cells.has(coord):
			var field = asteroid_fields[coord]
			
			for asteroid in field.asteroids:
				# Draw asteroid
				draw_colored_polygon(asteroid.points, asteroid_color)
				draw_polyline(asteroid.points + [asteroid.points[0]], asteroid_outline_color, 2.0, true)
				
				# Draw crater
				draw_circle(asteroid.crater_pos, asteroid.crater_size, asteroid_color.darkened(0.2))
			
			# Debug visualization
			if debug_mode:
				# Draw grid coordinate
				var text = "A(%d,%d)" % [field.grid_x, field.grid_y]
				var text_pos = Vector2(
					field.position.x - 30,
					field.position.y + 25  # Offset to not overlap with asteroids
				)
				
				# Draw text with outline for better visibility
				draw_string_outline(
					ThemeDB.fallback_font,
					text_pos,
					text,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					14,
					2,
					Color.BLACK
				)
				draw_string(
					ThemeDB.fallback_font,
					text_pos,
					text,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					14,
					Color.WHITE
				)
