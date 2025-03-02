extends Node

# Preload required generators
const MoonGeneratorClass = preload("res://moon_generator.gd")
const PlanetGeneratorClass = preload("res://planet_generator.gd")
const AtmosphereGeneratorClass = preload("res://atmosphere_generator.gd")

# Planet generation parameters
@export var planet_percentage = 10  # Percentage of grid cells that will contain planets
@export var minimum_planets = 5     # Minimum number of planets to generate
@export var moon_chance = 40        # Percentage chance for a planet to have moons
@export var max_moons = 2           # Maximum number of moons per planet
@export var moon_orbit_factor = 0.05      # Factor to slow down moon orbits (lower = slower)
@export var cell_margin = 0.2       # Margin from cell edges (as percentage of cell size)

# Reference to the grid
var grid = null

# Arrays to track spawned planets
var planet_positions = []
var planet_data = []  # Stores additional planet data like size, color, etc.

# Texture caches
var generated_planet_textures = {}
var generated_moon_textures = {}
var generated_atmosphere_textures = {}

# Debug flags
var debug_mode = true

func _ready():
	grid = get_node_or_null("/root/Main/Grid")
	if not grid:
		push_error("ERROR: Grid not found for planet spawning!")
		return
	
	# Connect to grid seed change signal if available
	if grid.has_signal("_seed_changed"):
		grid.connect("_seed_changed", _on_grid_seed_changed)

# Function to generate planets in grid cells
func generate_planets():
	# Clear existing planet data
	planet_positions.clear()
	planet_data.clear()
	generated_planet_textures.clear()
	generated_moon_textures.clear()
	generated_atmosphere_textures.clear()
	
	# Make sure grid is ready
	if grid.cell_contents.size() == 0:
		return
	
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
		
		# Generate a unique seed for this planet
		var planet_seed = grid.seed_value + x * 10000 + y * 1000
		
		# Calculate the world position at cell center
		var world_pos = Vector2(
			x * grid.cell_size.x + grid.cell_size.x / 2,
			y * grid.cell_size.y + grid.cell_size.y / 2
		)
		
		# Determine if this planet has moons
		var has_moons = rng.randi() % 100 < moon_chance
		var num_moons = rng.randi_range(1, max_moons) if has_moons else 0
		
		# Generate moon data if applicable
		var moons = []
		if has_moons:
			for m in range(num_moons):
				# Generate a unique seed for this moon
				var moon_seed = planet_seed + m * 100
				
				# Get moon texture from generator
				var moon_texture = MoonGeneratorClass.get_moon_texture(moon_seed)
				
				# Store in our cache for quick access
				var moon_key = str(moon_seed)
				generated_moon_textures[moon_key] = moon_texture
				
				# Determine moon pixel size from the generated texture
				var moon_generator = MoonGeneratorClass.new()
				var moon_pixel_size = moon_generator.get_moon_size(moon_seed)
				
				# Calculate moon parameters
				var moon_radius = moon_pixel_size / 2.0
				var planet_radius = 256 / 2.0  # Planet size is always 256x256
				var padding = rng.randf_range(10, 30)
				var moon_orbit_distance = planet_radius + moon_radius + padding
				
				var moon_angle = rng.randf_range(0, TAU)
				
				moons.append({
					"seed": moon_seed,
					"distance": moon_orbit_distance,
					"angle": moon_angle,
					"scale": 1.0,  # ALWAYS EXACTLY 1.0 - NO SCALING
					"orbit_speed": rng.randf_range(0.2, 0.5) * moon_orbit_factor,
					"phase_offset": rng.randf_range(0, TAU),
					"pixel_size": moon_pixel_size
				})
		
		# Get planet theme and generate atmosphere data
		var planet_generator = PlanetGeneratorClass.new()
		var planet_theme = planet_generator.get_planet_theme(planet_seed)
		
		# Generate atmosphere data
		var atmosphere_generator = AtmosphereGeneratorClass.new()
		var atmosphere_data = atmosphere_generator.generate_atmosphere_data(planet_theme, planet_seed)
		
		# Store planet position and data
		planet_positions.append({
			"position": world_pos,
			"grid_x": x,
			"grid_y": y
		})
		
		planet_data.append({
			"seed": planet_seed,
			"scale": 1.0,  # ALWAYS EXACTLY 1.0 - NO SCALING
			"pixel_size": 256,  # Force planet size to exactly 256x256
			"moons": moons,
			"name": generate_planet_name(x, y),
			"theme": planet_theme,
			"atmosphere": atmosphere_data
		})
		
		# Reserve this cell and adjacent cells
		for dy in range(-1, 2):  # -1, 0, 1
			for dx in range(-1, 2):  # -1, 0, 1
				var nx = x + dx
				var ny = y + dy
				
				# Only reserve valid positions
				if grid.is_valid_position(nx, ny):
					reserved_cells[Vector2i(nx, ny)] = true
		
		# Stop if we've placed enough planets
		if actual_planet_count >= planet_count:
			break
	
	# Force grid redraw
	grid.queue_redraw()

# Method to draw planets with moons - optimized for speed
func draw_planets(canvas: CanvasItem, loaded_cells: Dictionary):
	# Get current time for animation
	var time = Time.get_ticks_msec() / 1000.0
	
	# For each loaded cell
	for cell_pos in loaded_cells.keys():
		var x = int(cell_pos.x)
		var y = int(cell_pos.y)
		
		# Only process if this cell contains a planet
		if y < grid.cell_contents.size() and x < grid.cell_contents[y].size() and grid.cell_contents[y][x] == grid.CellContent.PLANET:
			# Find planet data
			var planet_index = -1
			for i in range(planet_positions.size()):
				if planet_positions[i].grid_x == x and planet_positions[i].grid_y == y:
					planet_index = i
					break
			
			if planet_index != -1:
				var planet = planet_data[planet_index]
				var planet_seed = planet.seed
				
				# Get planet textures from cache or generate them
				var planet_key = str(planet_seed)
				var planet_textures = null
				
				if generated_planet_textures.has(planet_key):
					planet_textures = generated_planet_textures[planet_key]
				else:
					# Generate planet textures if not in cache
					planet_textures = PlanetGeneratorClass.get_planet_texture(planet_seed)
					generated_planet_textures[planet_key] = planet_textures
				
				# Get atmosphere texture from cache or generate it
				var atmosphere_texture = null
				if generated_atmosphere_textures.has(planet_key):
					atmosphere_texture = generated_atmosphere_textures[planet_key]
				else:
					# Generate atmosphere texture if not in cache
					var atmosphere_generator = AtmosphereGeneratorClass.new()
					atmosphere_texture = atmosphere_generator.generate_atmosphere_texture(
						planet.theme, 
						planet_seed,
						planet.atmosphere.color,
						planet.atmosphere.thickness
					)
					generated_atmosphere_textures[planet_key] = atmosphere_texture
				
				# Get planet texture
				var planet_texture = planet_textures[0]
				
				# Always use 256x256 size for planets
				var planet_size = Vector2(256, 256)
				
				# CRITICAL: Reset transform before drawing
				canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
				
				# Draw the atmosphere first (below planet)
				if atmosphere_texture:
					canvas.draw_set_transform(planet_positions[planet_index].position, 0, Vector2.ONE)
					canvas.draw_texture(atmosphere_texture, -Vector2(atmosphere_texture.get_width(), atmosphere_texture.get_height()) / 2, Color.WHITE)
					canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
				
				# Draw the planet at exact pixel size - NEVER SCALE, NO ROTATION
				canvas.draw_set_transform(planet_positions[planet_index].position, 0, Vector2.ONE)
				canvas.draw_texture(planet_texture, -planet_size / 2, Color.WHITE)
				
				# Reset transform immediately after drawing
				canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
				
				# Draw moons that should appear BEHIND the planet
				if planet.has("moons"):
					for moon in planet.moons:
						# Update moon angle based on time and orbit speed
						var moon_angle = moon.angle + time * moon.orbit_speed
						
						# Add phase offset for orbital variety
						moon_angle += moon.phase_offset
						
						# Calculate moon position WITHOUT tilt (flat orbits)
						var moon_pos = planet_positions[planet_index].position + Vector2(
							cos(moon_angle) * moon.distance,
							sin(moon_angle) * moon.distance
						)
						
						# Determine if moon is behind the planet based on Y position
						if sin(moon_angle) > 0:  # Moon is in the "back" half of the orbit
							draw_procedural_moon(canvas, moon, moon_pos)
				
				# Now draw moons that should appear IN FRONT of the planet
				if planet.has("moons"):
					for moon in planet.moons:
						# Update moon angle based on time and orbit speed
						var moon_angle = moon.angle + time * moon.orbit_speed
						
						# Add phase offset for orbital variety
						moon_angle += moon.phase_offset
						
						# Calculate moon position WITHOUT tilt (flat orbits)
						var moon_pos = planet_positions[planet_index].position + Vector2(
							cos(moon_angle) * moon.distance,
							sin(moon_angle) * moon.distance
						)
						
						# Determine if moon is in front of the planet based on Y position
						if sin(moon_angle) <= 0:  # Moon is in the "front" half of the orbit
							draw_procedural_moon(canvas, moon, moon_pos)

# Helper function to draw a procedurally generated moon at a specific position
func draw_procedural_moon(canvas: CanvasItem, moon, moon_pos: Vector2):
	# Get the moon texture from our cache or generate a new one
	var moon_key = str(moon.seed)
	var moon_texture = null
	
	if generated_moon_textures.has(moon_key):
		moon_texture = generated_moon_textures[moon_key]
	else:
		# Generate the moon texture and cache it
		moon_texture = MoonGeneratorClass.get_moon_texture(moon.seed)
		generated_moon_textures[moon_key] = moon_texture
	
	if moon_texture:
		# Calculate the exact moon size in pixels
		var moon_size = Vector2(moon.pixel_size, moon.pixel_size)
		
		# Draw the moon at exact pixel size with NO SCALING and NO ROTATION
		canvas.draw_set_transform(moon_pos, 0, Vector2.ONE)
		canvas.draw_texture(moon_texture, -moon_size / 2, Color.WHITE)
		canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)  # Reset transform
	else:
		# Fallback to drawing a circle if texture generation failed
		var moon_radius = moon.pixel_size / 2.0
		canvas.draw_circle(moon_pos, moon_radius, Color(0.9, 0.9, 0.9))

# Function to get all planet positions (used by main.gd)
func get_all_planet_positions():
	return planet_positions

# Function to reset planets (used when seed changes)
func reset_planets():
	call_deferred("generate_planets")

# Handler for grid seed change
func _on_grid_seed_changed(_new_seed = null):
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
