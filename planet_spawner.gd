extends Node

# Preload required generators
const MoonGeneratorClass = preload("res://moon_generator.gd")
const PlanetGeneratorClass = preload("res://planet_generator.gd")

# Planet generation parameters
@export var planet_percentage = 10  # Percentage of grid cells that will contain planets
@export var minimum_planets = 5     # Minimum number of planets to generate
@export var moon_chance = 40        # Percentage chance for a planet to have moons
@export var max_moons = 2           # Maximum number of moons per planet
@export var planet_rotation_factor = 0.02  # Factor to slow down planet rotation (lower = slower)
@export var moon_orbit_factor = 0.05      # Factor to slow down moon orbits (lower = slower)
@export var cell_margin = 0.2       # Margin from cell edges (as percentage of cell size)
@export var orbital_tilt = 0.2      # Tilt factor for orbital planes (0-1, 0=no tilt, 1=max tilt)

# Reference to the grid
var grid = null

# Arrays to track spawned planets
var planet_positions = []
var planet_data = []  # Stores additional planet data like size, color, etc.

# Fallback planet sprites (used if generation fails)
var fallback_planet_sprites = []
var moon_sprites = []   # Will keep this for fallback

# Texture caches
var generated_planet_textures = {}
var generated_moon_textures = {}

func _ready():
	grid = get_node_or_null("/root/Main/Grid")
	if not grid:
		push_error("ERROR: Grid not found for planet spawning!")
		return
	
	# Connect to grid seed change signal if available
	if grid.has_signal("_seed_changed"):
		grid.connect("_seed_changed", _on_grid_seed_changed)
	
	# Load fallback planet sprites
	load_fallback_sprites()

# Function to load fallback planet sprites
func load_fallback_sprites():
	# Clear existing sprites
	fallback_planet_sprites.clear()
	moon_sprites.clear()
	
	# Load planet sprites as fallbacks
	var planet_paths = [
		"res://sprites/planets/planet_1.png",
		"res://sprites/planets/planet_2.png",
		"res://sprites/planets/planet_3.png",
		"res://sprites/planets/planet_4.png",
		"res://sprites/planets/planet_5.png"
	]
	
	for path in planet_paths:
		if ResourceLoader.exists(path):
			var texture = load(path)
			if texture:
				fallback_planet_sprites.append(texture)
	
	# Load moon sprites (for fallback)
	var moon_paths = [
		"res://sprites/moons/moon_1.png",
		"res://sprites/moons/moon_2.png",
		"res://sprites/moons/moon_3.png"
	]
	
	for path in moon_paths:
		if ResourceLoader.exists(path):
			var texture = load(path)
			if texture:
				moon_sprites.append(texture)
	
	# Create fallback sprites if none were loaded
	if fallback_planet_sprites.size() == 0:
		var image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for x in range(64):
			for y in range(64):
				var dist = Vector2(x - 32, y - 32).length()
				if dist < 30:
					image.set_pixel(x, y, Color(1, 1, 1, 1))
		var fallback_texture = ImageTexture.create_from_image(image)
		fallback_planet_sprites.append(fallback_texture)
	
	if moon_sprites.size() == 0:
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
	# Clear existing planet data
	planet_positions.clear()
	planet_data.clear()
	generated_planet_textures.clear()
	generated_moon_textures.clear()
	
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
		
		# Generate planet textures
		var planet_textures = PlanetGeneratorClass.get_planet_texture(planet_seed)
		var planet_texture = planet_textures[0]  # Main planet texture
		var atmosphere_texture = planet_textures[1]  # Atmosphere texture
		var planet_pixel_size = planet_textures[2]  # Planet size
		
		# Store in cache
		var planet_key = str(planet_seed)
		generated_planet_textures[planet_key] = planet_textures
		
		# Calculate the safe area within the cell considering the planet size
		var cell_min_dimension = min(grid.cell_size.x, grid.cell_size.y) * (1.0 - 2 * cell_margin)
		
		# Scale the planet if needed to fit cell
		var scale = 1.0
		#if planet_pixel_size > cell_min_dimension:
			#scale = cell_min_dimension / planet_pixel_size
		
		# Calculate the visual radius of the planet with scaling
		var planet_radius = planet_pixel_size * scale / 2
		
		# Determine if this planet has moons
		var has_moons = rng.randi() % 100 < moon_chance
		var num_moons = rng.randi_range(1, max_moons) if has_moons else 0
		
		# Calculate the safe area within the cell accounting for planet radius
		var safe_width = grid.cell_size.x * (1.0 - 2 * cell_margin)
		var safe_height = grid.cell_size.y * (1.0 - 2 * cell_margin)
		
		# If planet has moons, we need to account for their orbits in positioning
		var max_moon_distance = 0
		
		# Generate moon data if applicable
		var moons = []
		if has_moons:
			# First pass to calculate the largest moon orbit radius
			for m in range(num_moons):
				# Generate a unique seed for this moon
				var moon_seed = planet_seed + m * 100
				
				# Determine moon pixel size based on seed
				var moon_generator = MoonGeneratorClass.new()
				var moon_pixel_size = moon_generator.get_moon_size(moon_seed)
				
				# Calculate moon parameters
				var moon_radius = moon_pixel_size / 2.0
				var padding = rng.randf_range(10, 30)
				var moon_orbit_distance = planet_radius + moon_radius + padding
				
				if moon_orbit_distance > max_moon_distance:
					max_moon_distance = moon_orbit_distance
			
			# Calculate the effective radius including moons
			var effective_radius = planet_radius + max_moon_distance
			
			# Further restrict safe area to account for moons
			safe_width -= 2 * effective_radius
			safe_height -= 2 * effective_radius
			
			# Ensure we have some minimum safe area
			safe_width = max(safe_width, 10)
			safe_height = max(safe_height, 10)
			
			# Generate moon data for each moon
			for m in range(num_moons):
				# Generate a unique seed for this moon
				var moon_seed = planet_seed + m * 100
				
				# Get moon texture from generator
				var moon_texture = MoonGeneratorClass.get_moon_texture(moon_seed)
				
				# Store in our cache for quick access
				var moon_key = str(moon_seed)
				generated_moon_textures[moon_key] = moon_texture
				
				# Determine moon pixel size
				var moon_generator = MoonGeneratorClass.new()
				var moon_pixel_size = moon_generator.get_moon_size(moon_seed)
				
				# Calculate moon parameters
				var moon_radius = moon_pixel_size / 2.0
				var padding = rng.randf_range(10, 30)
				var moon_orbit_distance = planet_radius + moon_radius + padding
				
				var moon_angle = rng.randf_range(0, TAU)
				
				# Scaling for the moon - smaller moons look better
				var moon_scale = scale * rng.randf_range(0.5, 0.7)
				
				# Add orbital inclination for 3D effect
				var orbit_tilt = rng.randf_range(-orbital_tilt, orbital_tilt)
				
				moons.append({
					"seed": moon_seed,
					"distance": moon_orbit_distance,
					"angle": moon_angle,
					"scale": moon_scale,
					"orbit_speed": rng.randf_range(0.2, 0.5) * moon_orbit_factor,
					"tilt": orbit_tilt,
					"phase_offset": rng.randf_range(0, TAU),
					"pixel_size": moon_pixel_size
				})
		else:
			# No moons, just account for planet radius in safe area
			safe_width -= 2 * planet_radius
			safe_height -= 2 * planet_radius
			safe_width = max(safe_width, 10)
			safe_height = max(safe_height, 10)
		
		# Generate random offset within safe area
		var offset_x = rng.randf_range(-safe_width/2, safe_width/2)
		var offset_y = rng.randf_range(-safe_height/2, safe_height/2)
		
		# Calculate final world position with randomized offset
		var world_pos = Vector2(
			x * grid.cell_size.x + grid.cell_size.x / 2 + offset_x,
			y * grid.cell_size.y + grid.cell_size.y / 2 + offset_y
		)
		
		# Store planet position and data
		planet_positions.append({
			"position": world_pos,
			"grid_x": x,
			"grid_y": y
		})
		
		planet_data.append({
			"seed": planet_seed,
			"scale": scale,
			"pixel_size": planet_pixel_size,
			"moons": moons,
			"rotation_speed": rng.randf_range(0.02, 0.05) * planet_rotation_factor,
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
	
	# Force grid redraw
	grid.queue_redraw()

# Method to draw planets with moons that have depth sorting
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
				
				# Debug logging
				print("--- Planet Debug ---")
				print("Cell size: ", grid.cell_size)
				print("Planet pixel size: ", planet.pixel_size)
				print("Planet position: ", planet_positions[planet_index].position)
				print("Planet data scale: ", planet.scale)
				
				# Get planet textures from cache or generate them
				var planet_key = str(planet_seed)
				var planet_textures = null
				
				if generated_planet_textures.has(planet_key):
					planet_textures = generated_planet_textures[planet_key]
				else:
					# Generate planet textures if not in cache
					planet_textures = PlanetGeneratorClass.get_planet_texture(planet_seed)
					generated_planet_textures[planet_key] = planet_textures
				
				# Get planet texture and atmosphere texture
				var planet_texture = planet_textures[0]
				var atmosphere_texture = planet_textures[1]
				
				# IMPORTANT CHANGE: Always use full pixel size, remove scaling
				var texture_size = Vector2(planet.pixel_size, planet.pixel_size)
				
				print("Texture size: ", texture_size)
				
				# Calculate rotation based on time and planet's rotation speed
				var rotation = time * planet.rotation_speed
				
				# Draw atmosphere first (behind the planet)
				canvas.draw_set_transform(planet_positions[planet_index].position, rotation, Vector2.ONE)
				canvas.draw_texture(atmosphere_texture, -texture_size / 2, Color.WHITE)
				
				# Draw the planet
				canvas.draw_set_transform(planet_positions[planet_index].position, rotation, Vector2.ONE)
				canvas.draw_texture(planet_texture, -Vector2(planet.pixel_size, planet.pixel_size) / 2, Color.WHITE)
				canvas.draw_set_transform(planet_positions[planet_index].position, 0, Vector2(1, 1))  # Reset transform
				
				# Now draw moons that should appear IN FRONT of the planet
				if planet.has("moons"):
					for moon in planet.moons:
						# Update moon angle based on time and orbit speed
						var moon_angle = moon.angle + time * moon.orbit_speed
						
						# Add phase offset for orbital variety
						moon_angle += moon.phase_offset
						
						# Calculate moon position with tilt (simulating orbital inclination)
						var orbit_y_scale = 1.0 - abs(moon.tilt)  # Compress Y axis based on tilt
						var moon_pos = planet_positions[planet_index].position + Vector2(
							cos(moon_angle) * moon.distance,
							sin(moon_angle) * moon.distance * orbit_y_scale
						)
						
						# Determine if moon is in front of the planet based on Y position
						# (if moon Y position <= planet center Y, it's in front)
						if sin(moon_angle) <= 0:  # Moon is in the "front" half of the orbit
							draw_procedural_moon(canvas, moon, moon_pos, time)

# Helper function to draw a procedurally generated moon at a specific position
func draw_procedural_moon(canvas: CanvasItem, moon, moon_pos: Vector2, time: float):
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
		# Calculate size based on moon's settings
		var moon_size = Vector2(moon.pixel_size, moon.pixel_size)
		
		# Add slight moon rotation for extra realism
		var moon_rotation = time * moon.orbit_speed * 0.5
		
		# Draw the moon
		canvas.draw_set_transform(moon_pos, moon_rotation, Vector2(moon.scale, moon.scale))
		canvas.draw_texture(moon_texture, -moon_size / 2, Color.WHITE)
		canvas.draw_set_transform(moon_pos, 0, Vector2(1, 1))  # Reset transform
	else:
		# Fallback to drawing a circle if texture generation failed
		var moon_size = 10 * moon.scale
		canvas.draw_circle(moon_pos, moon_size, Color(0.9, 0.9, 0.9))

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
