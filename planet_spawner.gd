extends Node2D

signal planet_spawned(planet_position, grid_x, grid_y)

# Planet spawn parameters
@export var planet_probability = 15  # Percentage chance for a cell to have a planet
@export var planet_size_min = 0.3
@export var planet_size_max = 0.5

# Planet appearance
@export var planet_color_palette = [
	Color.WHITE, 
	Color.GREEN, 
	Color.RED, 
	Color(0.96, 0.96, 0.86),  # Light yellow
	Color.BLUE
]

# Reference to the grid
var grid = null
# Reference to asteroid spawner to check for conflicts
var asteroid_spawner = null

# Dictionary to store planet data
# Key: Vector2(x, y) for grid coords, Value: Dictionary with planet properties
var planets = {}

# Called when the node enters the scene tree
func _ready():
	# Find the grid
	grid = get_node_or_null("/root/Main/Grid")
	if not grid:
		push_error("ERROR: Grid not found for planet spawning!")
	
	# Find the asteroid spawner
	asteroid_spawner = get_node_or_null("/root/Main/AsteroidSpawner")

# Initialize planet spawning with specific grid and seed
func initialize(target_grid, seed_val):
	# Update grid reference
	grid = target_grid
	
	# Ensure asteroid spawner is referenced
	if asteroid_spawner == null:
		asteroid_spawner = get_node_or_null("/root/Main/AsteroidSpawner")
	
	# Generate planets
	generate_planets(seed_val)
	
	print("Planet spawner initialized - Total planets: ", planets.size())
	return planets.size() > 0

# Check if a planet can be placed at the given position
func can_place_planet(x, y):
	# Check if the specific cell is already occupied
	if grid.is_cell_occupied(x, y):
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
			
			# Prevent planets from being too close to each other
			if planets.has(Vector2(adj_x, adj_y)):
				return false
			
			# Prevent planets near asteroid fields
			if asteroid_spawner and asteroid_spawner.get_asteroid_field_at(adj_x, adj_y) != null:
				return false
	
	# If no conflicts were found, we can place a planet here
	return true

# Main planet generation function
func generate_planets(seed_val):
	# Clear any existing planets
	planets.clear()
	
	# Create a new random number generator
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val
	
	# First pass: determine which cells will have planets
	for y in range(int(grid.grid_size.y)):
		for x in range(int(grid.grid_size.x)):
			# Skip boundary cells - they must always remain empty
			if grid.is_boundary_cell(x, y):
				continue
			
			var rand_value = rng.randi() % 100
			
			if rand_value < planet_probability and can_place_planet(x, y):
				# Set up planet data
				var planet_data = {
					"position": Vector2(
						x * grid.cell_size.x + grid.cell_size.x / 2,
						y * grid.cell_size.y + grid.cell_size.y / 2
					),
					"size": generate_planet_size(seed_val, x, y),
					"color": generate_planet_color(seed_val, x, y),
					"grid_x": x,
					"grid_y": y
				}
				
				# Store planet data in dictionary
				planets[Vector2(x, y)] = planet_data
				
				# Mark the cell as occupied
				grid.mark_cell_occupied(x, y, grid.CellContent.PLANET)
				
				# Signal that a planet was spawned
				emit_signal("planet_spawned", planet_data.position, x, y)
	
	# Ensure at least one planet exists
	if planets.size() == 0:
		_force_spawn_fallback_planet(seed_val)
	
	print("Generated planets with seed: ", seed_val, " - Total planets created: ", planets.size())

# Force spawn a fallback planet
func _force_spawn_fallback_planet(seed_val):
	print("No planets generated! Forcing a planet at fallback position")
	
	# Try position (5,5) first
	var fallback_positions = [
		Vector2(5, 5),
		Vector2(4, 4),
		Vector2(6, 6),
		Vector2(3, 3),
		Vector2(7, 7)
	]
	
	for pos in fallback_positions:
		var x = int(pos.x)
		var y = int(pos.y)
		
		if grid.is_valid_position(x, y) and not grid.is_boundary_cell(x, y) and can_place_planet(x, y):
			var planet_data = {
				"position": Vector2(
					x * grid.cell_size.x + grid.cell_size.x / 2,
					y * grid.cell_size.y + grid.cell_size.y / 2
				),
				"size": generate_planet_size(seed_val, x, y),
				"color": generate_planet_color(seed_val, x, y),
				"grid_x": x,
				"grid_y": y
			}
			
			# Store planet data
			planets[Vector2(x, y)] = planet_data
			
			# Mark the cell as occupied
			grid.mark_cell_occupied(x, y, grid.CellContent.PLANET)
			
			# Signal that a planet was spawned
			emit_signal("planet_spawned", planet_data.position, x, y)
			
			print("Forced planet creation at position: (", x, ",", y, ")")
			return

# Helper function to generate consistent planet size
func generate_planet_size(seed_val, x, y):
	var size_rng = RandomNumberGenerator.new()
	size_rng.seed = seed_val + y * 1000 + x
	return size_rng.randf_range(planet_size_min, planet_size_max)

# Helper function to generate consistent planet color
func generate_planet_color(seed_val, x, y):
	var color_rng = RandomNumberGenerator.new()
	color_rng.seed = seed_val + y * 1000 + x
	return planet_color_palette[color_rng.randi() % planet_color_palette.size()]

# Get all planet positions for external use
func get_all_planets():
	var planet_list = []
	
	for coord in planets.keys():
		planet_list.append(planets[coord])
	
	return planet_list

# Get a specific planet at grid coordinates
func get_planet_at(grid_x, grid_y):
	var coord = Vector2(grid_x, grid_y)
	if planets.has(coord):
		return planets[coord]
	return null

# Draw all planets in loaded chunks
func _draw():
	if not grid or planets.is_empty():
		return
	
	for coord in planets.keys():
		# Only draw planets in loaded chunks
		if grid.loaded_cells.has(coord):
			var planet = planets[coord]
			var cell_center = planet.position
			var shape_size = min(grid.cell_size.x, grid.cell_size.y) * planet.size
			
			# Draw the planet circle
			draw_circle(cell_center, shape_size, planet.color)
			
			# Add outline
			draw_arc(cell_center, shape_size, 0, TAU, 32, planet.color.darkened(0.2), 2.0, true)
			
			# Add surface details (rings or features)
			var ring_radius = shape_size * 0.7
			draw_arc(cell_center, ring_radius, 0, PI, 16, planet.color.lightened(0.1), 1.5)
			draw_arc(cell_center, ring_radius, PI, TAU, 16, planet.color.lightened(0.1), 1.5)

# Call this function when loaded chunks change
func update_visibility():
	queue_redraw()
