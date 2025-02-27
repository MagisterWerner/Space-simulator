extends Node

# Planet generation parameters
@export var planet_percentage = 10  # Percentage of grid cells that will contain planets
@export var minimum_planets = 5     # Minimum number of planets to generate
@export var moon_chance = 40        # Percentage chance for a planet to have moons
@export var max_moons = 2           # Maximum number of moons per planet
@export var planet_rotation_factor = 0.02  # Factor to slow down planet rotation (lower = slower)
@export var moon_orbit_factor = 0.05      # Factor to slow down moon orbits (lower = slower)
@export var cell_margin = 0.9       # Percentage of cell to use (allows some margin)

# Reference to the grid
var grid = null

# Array to track spawned planets
var planet_positions = []
var planet_data = []  # Stores additional planet data like size, color, etc.

# Planet size and color arrays (for fallback)
var planet_sizes = []
var planet_colors = []

# Arrays to store planet and moon sprites
var planet_sprites = []
var moon_sprites = []

# Planet color palette for fallback drawing
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
	
	# Load planet and moon sprites
	load_sprites()
	
	print("Planet spawner initialized")

# Function to load planet and moon sprites
func load_sprites():
	# Clear existing sprites
	planet_sprites.clear()
	moon_sprites.clear()
	
	# Load planet sprites
	var planet_paths = [
		"res://sprites/planets/planet_1.png",
		"res://sprites/planets/planet_2.png",
		"res://sprites/planets/planet_3.png",
		"res://sprites/planets/planet_4.png",
		"res://sprites/planets/planet_5.png"
	]
	
	for path in planet_paths:
		var texture = load(path)
		if texture:
			planet_sprites.append(texture)
		else:
			push_warning("Failed to load planet sprite: " + path)
	
	# Load moon sprites
	var moon_paths = [
		"res://sprites/moons/moon_1.png",
		"res://sprites/moons/moon_2.png",
		"res://sprites/moons/moon_3.png"
	]
	
	for path in moon_paths:
		var texture = load(path)
		if texture:
			moon_sprites.append(texture)
		else:
			push_warning("Failed to load moon sprite: " + path)
	
	print("Loaded " + str(planet_sprites.size()) + " planet sprites and " + str(moon_sprites.size()) + " moon sprites")
	
	# Create fallback sprites if none were loaded
	if planet_sprites.size() == 0:
		print("No planet sprites found. Creating fallback empty texture.")
		var image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for x in range(64):
			for y in range(64):
				var dist = Vector2(x - 32, y - 32).length()
				if dist < 30:
					image.set_pixel(x, y, Color(1, 1, 1, 1))
		var fallback_texture = ImageTexture.create_from_image(image)
		planet_sprites.append(fallback_texture)
	
	if moon_sprites.size() == 0:
		print("No moon sprites found. Creating fallback empty texture.")
		var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for x in range(32):
			for y in range(32):
				var dist = Vector2(x - 16, y - 16).length()
				if dist < 14:
					image.set_pixel(x, y, Color(0.9, 0.9, 0.9, 1))
		var fallback_texture = ImageTexture.create_from_image(image)
		moon_sprites.append(fallback_texture)

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
		
		# Choose a random color from the palette (for fallback drawing)
		var color_index = rng.randi() % planet_color_palette.size()
		var planet_color = planet_color_palette[color_index]
		planet_colors[y][x] = planet_color
		
		# Select a random planet sprite
		var planet_sprite_idx = rng.randi() % planet_sprites.size() if planet_sprites.size() > 0 else 0
		
		# Get planet size from the sprite size
		var planet_texture = planet_sprites[planet_sprite_idx]
		var texture_size = planet_texture.get_size()
		var cell_min_dimension = min(grid.cell_size.x, grid.cell_size.y) * cell_margin
		var planet_pixel_size = max(texture_size.x, texture_size.y)
		
		# Start with 1:1 pixel scale (no scaling)
		var scale = 1.0
		
		# Only scale down if the planet is too large for the cell
		if planet_pixel_size > cell_min_dimension:
			scale = cell_min_dimension / planet_pixel_size
			print("Scaling down planet ", planet_sprite_idx, " from ", planet_pixel_size, " to fit cell (scale: ", scale, ")")
		else:
			print("Using original size for planet ", planet_sprite_idx, " (", planet_pixel_size, " pixels)")
		
		# Determine if this planet has moons
		var has_moons = rng.randi() % 100 < moon_chance
		var num_moons = rng.randi_range(1, max_moons) if has_moons else 0
		
		# Generate moon data if applicable
		var moons = []
		if has_moons and moon_sprites.size() > 0:
			for m in range(num_moons):
				# Generate moon data
				var moon_sprite_idx = rng.randi() % moon_sprites.size()
				var moon_texture = moon_sprites[moon_sprite_idx]
				var moon_texture_size = moon_texture.get_size()
				
				# Calculate moon parameters
				var planet_radius = texture_size.x * scale / 2  # Actual visual radius of planet with scaling
				var moon_radius = moon_texture_size.x / 2       # Half the moon size (unscaled)
				var padding = rng.randf_range(10, 30)           # Space between planet edge and moon
				var moon_orbit_distance = planet_radius + moon_radius + padding
				
				var moon_angle = rng.randf_range(0, TAU)
				
				# Scaling for the moon - smaller moons look better
				var moon_scale = scale * rng.randf_range(0.5, 0.7)
				
				moons.append({
					"sprite_idx": moon_sprite_idx,
					"distance": moon_orbit_distance,
					"angle": moon_angle,
					"scale": moon_scale,
					"orbit_speed": rng.randf_range(0.2, 0.5) * moon_orbit_factor  # Slowed down orbit speed
				})
		
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
			"sprite_idx": planet_sprite_idx,
			"color": planet_color,
			"scale": scale,
			"pixel_size": planet_pixel_size,
			"moons": moons,
			"rotation_speed": rng.randf_range(0.02, 0.05) * planet_rotation_factor,  # Very slow rotation
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

# New method to draw planets using sprites in pixel-perfect mode
func draw_planets(canvas: CanvasItem, loaded_cells: Dictionary):
	if not grid:
		return
	
	# Get current time for animation
	var time = Time.get_ticks_msec() / 1000.0
	
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
			
			# Find planet data
			var planet_index = -1
			for i in range(planet_positions.size()):
				if planet_positions[i].grid_x == x and planet_positions[i].grid_y == y:
					planet_index = i
					break
			
			if planet_index != -1:
				var planet = planet_data[planet_index]
				var sprite_idx = planet.sprite_idx
				
				# Calculate rotation based on time and planet's rotation speed
				var rotation = time * planet.rotation_speed
				
				# Draw the planet sprite if available, otherwise fallback to circle
				if planet_sprites.size() > 0 and sprite_idx < planet_sprites.size():
					var texture = planet_sprites[sprite_idx]
					var texture_size = texture.get_size()
					var scale = planet.scale
					
					# Draw with rotation, ensuring pixel-perfectness by rounding position
					canvas.draw_set_transform(cell_center, rotation, Vector2(scale, scale))
					canvas.draw_texture(texture, -texture_size / 2, Color.WHITE)
					canvas.draw_set_transform(cell_center, 0, Vector2(1, 1))  # Reset transform
				else:
					# Fallback to drawing a circle
					var shape_size = min(grid.cell_size.x, grid.cell_size.y) * 0.3
					canvas.draw_circle(cell_center, shape_size, planet.color)
					canvas.draw_arc(cell_center, shape_size, 0, TAU, 32, planet.color.darkened(0.2), 2.0, true)
				
				# Draw moons
				if planet.has("moons") and moon_sprites.size() > 0:
					for moon in planet.moons:
						# Update moon angle based on time and orbit speed
						var moon_angle = moon.angle + time * moon.orbit_speed
						var moon_pos = cell_center + Vector2(cos(moon_angle), sin(moon_angle)) * moon.distance
						
						# Draw the moon sprite
						if moon.sprite_idx < moon_sprites.size():
							var moon_texture = moon_sprites[moon.sprite_idx]
							var moon_texture_size = moon_texture.get_size()
							
							canvas.draw_set_transform(moon_pos, 0, Vector2(moon.scale, moon.scale))
							canvas.draw_texture(moon_texture, -moon_texture_size / 2, Color.WHITE)
							canvas.draw_set_transform(moon_pos, 0, Vector2(1, 1))  # Reset transform
						else:
							# Fallback to drawing a circle for the moon
							var moon_size = min(grid.cell_size.x, grid.cell_size.y) * 0.1
							canvas.draw_circle(moon_pos, moon_size, Color(0.9, 0.9, 0.9))

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
