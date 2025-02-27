extends Node

# Planet generation parameters
@export var planet_percentage = 10  # Percentage of grid cells that will contain planets
@export var minimum_planets = 5     # Minimum number of planets to generate
@export var min_planet_size = 0.25  # Minimum planet size as fraction of cell size
@export var max_planet_size = 0.4   # Maximum planet size as fraction of cell size

# Reference to the grid
var grid = null

# Array to track spawned planets
var planet_positions = []
var planet_data = []  # Stores additional planet data like size, color, etc.

# 2D arrays to store planet sizes and colors (moved from grid)
var planet_sizes = []
var planet_colors = []

# Planet color palette
var planet_color_palette = [
	Color.WHITE, 
	Color.GREEN, 
	Color.RED, 
	Color(0.96, 0.96, 0.86),  # Light yellow
	Color.BLUE
]

# Called when the node enters the scene tree for the first time
func _ready():
	grid = get_node_or_null("/root/Main/Grid")
	if not grid:
		push_error("ERROR: Grid not found for planet spawning!")
		return
	
	# Connect to grid seed change signal if available
	if grid.has_signal("seed_changed"):
		grid.connect("seed_changed", _on_grid_seed_changed)
	
	print("Planet spawner initialized")

# Function to generate planets in grid cells
func generate_planets():
	# Clear existing planet data from planet_data array
	planet_positions.clear()
	planet_data.clear()
	
	# Initialize planet_sizes and planet_colors arrays
	planet_sizes = []
	planet_colors = []
	
	# Make sure grid is ready
	if grid.cell_contents.size() == 0:
		print("ERROR: Grid content arrays not initialized yet")
		return
	
	# Initialize the planet arrays to match grid size
	for y in range(int(grid.grid_size.y)):
		planet_sizes.append([])
		planet_colors.append([])
		for x in range(int(grid.grid_size.x)):
			planet_sizes[y].append(0.0)
			planet_colors[y].append(Color.WHITE)
	
	print("Generating planets with seed: ", grid.seed_value)
	
	# Get a list of non-boundary cells for placing planets
	var available_cells = []
	for y in range(1, int(grid.grid_size.y) - 1):
		for x in range(1, int(grid.grid_size.x) - 1):
			# Skip boundary cells
			if grid.is_boundary_cell(x, y):
				continue
			
			# Add valid cells
			available_cells.append(Vector2i(x, y))
	
	# Create a Set to track reserved cells (cells that cannot have planets)
	var reserved_cells = {}
	
	# Determine how many planets to spawn
	var non_boundary_count = available_cells.size()
	var planet_count = max(minimum_planets, int(non_boundary_count * planet_percentage / 100.0))
	planet_count = min(planet_count, non_boundary_count)  # Cap at available cells
	
	print("Found ", non_boundary_count, " available cells - Spawning ", planet_count, " planets")
	
	# Setup RNG with the grid's seed
	var rng = RandomNumberGenerator.new()
	rng.seed = grid.seed_value
	
	var actual_planet_count = 0
	
	# Try multiple times to ensure we get enough planets
	for i in range(planet_count * 3):
		# Choose a random available cell that isn't reserved
		var avail_indices = []
		for j in range(available_cells.size()):
			var pos = available_cells[j]
			if not reserved_cells.has(pos):
				avail_indices.append(j)
		
		if avail_indices.size() == 0:
			break  # No more available cells
		
		var idx = avail_indices[rng.randi() % avail_indices.size()]
		var planet_pos = available_cells[idx]
		var x = planet_pos.x
		var y = planet_pos.y
		
		# Set cell as planet in the grid
		grid.cell_contents[y][x] = grid.CellContent.PLANET
		actual_planet_count += 1
		
		# Generate random size
		var planet_size = rng.randf_range(min_planet_size, max_planet_size)
		planet_sizes[y][x] = planet_size
		
		# Choose a random color from the palette
		var color_index = rng.randi() % planet_color_palette.size()
		var planet_color = planet_color_palette[color_index]
		planet_colors[y][x] = planet_color
		
		# Store planet position and data
		var world_pos = Vector2(
			x * grid.cell_size.x + grid.cell_size.x / 2,
			y * grid.cell_size.y + grid.cell_size.y / 2
		)
		
		planet_positions.append({
			"position": world_pos,
			"grid_x": x,
			"grid_y": y
		})
		
		planet_data.append({
			"size": planet_size,
			"color": planet_color,
			"name": generate_planet_name(x, y)
		})
		
		# Reserve this cell and all cells within 2 cells distance (including diagonals)
		for dy in range(-2, 3):  # -2, -1, 0, 1, 2
			for dx in range(-2, 3):  # -2, -1, 0, 1, 2
				var nx = x + dx
				var ny = y + dy
				
				# Only reserve valid positions
				if grid.is_valid_position(nx, ny):
					reserved_cells[Vector2i(nx, ny)] = true
		
		# Stop if we've placed enough planets
		if actual_planet_count >= planet_count:
			break
	
	print("Planet generation complete - Total planets: ", actual_planet_count)
	
	# Force grid redraw
	grid.queue_redraw()

# New method to draw planets
func draw_planets(canvas: CanvasItem, loaded_cells: Dictionary):
	if not grid:
		return
	
	# For each loaded cell
	for cell_pos in loaded_cells.keys():
		var x = int(cell_pos.x)
		var y = int(cell_pos.y)
		
		# Only process if this cell contains a planet
		if y < grid.cell_contents.size() and x < grid.cell_contents[y].size() and grid.cell_contents[y][x] == grid.CellContent.PLANET:
			var cell_center = Vector2(
				x * grid.cell_size.x + grid.cell_size.x / 2.0,
				y * grid.cell_size.y + grid.cell_size.y / 2.0
			)
			
			# Draw a circle (planet) with outline
			var shape_size = min(grid.cell_size.x, grid.cell_size.y) * planet_sizes[y][x]
			canvas.draw_circle(cell_center, shape_size, planet_colors[y][x])
			canvas.draw_arc(cell_center, shape_size, 0, TAU, 32, planet_colors[y][x].darkened(0.2), 2.0, true)  # Outline
			
			# Add some detail to the planet (rings or surface features)
			var ring_radius = shape_size * 0.7
			canvas.draw_arc(cell_center, ring_radius, 0, PI, 16, planet_colors[y][x].lightened(0.1), 1.5)
			canvas.draw_arc(cell_center, ring_radius, PI, TAU, 16, planet_colors[y][x].lightened(0.1), 1.5)

# Function to get all planet positions (used by main.gd)
func get_all_planet_positions():
	return planet_positions

# Function to reset planets (used when seed changes)
func reset_planets():
	call_deferred("generate_planets")

# Handler for grid seed change
func _on_grid_seed_changed(new_seed = null):
	print("Planet spawner detected seed change, regenerating planets")
	call_deferred("generate_planets")

# Function to generate a planet name based on coordinates
func generate_planet_name(x, y):
	# Simple algorithm to create a unique planet name based on grid coordinates
	var consonants = ["b", "c", "d", "f", "g", "h", "j", "k", "l", "m", "n", "p", "r", "s", "t", "v", "z"]
	var vowels = ["a", "e", "i", "o", "u"]
	
	# Create a deterministic name based on coordinates and seed
	var rng = RandomNumberGenerator.new()
	rng.seed = grid.seed_value + (x * 100) + y
	
	var planet_name = ""

	# First syllable
	planet_name += consonants[rng.randi() % consonants.size()].to_upper()
	planet_name += vowels[rng.randi() % vowels.size()]

	# Second syllable
	planet_name += consonants[rng.randi() % consonants.size()]
	planet_name += vowels[rng.randi() % vowels.size()]

	# Add a number or hyphen followed by additional characters based on coordinates
	if rng.randi() % 2 == 0:
		# Add hyphen and letters
		planet_name += "-"
		planet_name += consonants[rng.randi() % consonants.size()].to_upper()
		planet_name += vowels[rng.randi() % vowels.size()]
	else:
		# Add numbers
		planet_name += " " + str((x + y) % 9 + 1)

	return planet_name

# Get a specific planet name (used by main.gd for messages)
func get_planet_name(x, y):
	for i in range(planet_positions.size()):
		if planet_positions[i].grid_x == x and planet_positions[i].grid_y == y:
			return planet_data[i].name
	
	# If not found, generate a name on the fly
	return generate_planet_name(x, y)
