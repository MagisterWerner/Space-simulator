# planet_spawner.gd
extends Node

const MoonGeneratorClass = preload("res://scripts/generators/moon_generator.gd")
const PlanetGeneratorClass = preload("res://scripts/generators/planet_generator.gd")
const AtmosphereGeneratorClass = preload("res://scripts/generators/atmosphere_generator.gd")

# Configuration parameters
@export var planet_percentage: int = 10
@export var minimum_planets: int = 5
@export var moon_chance: int = 40
@export var max_moons: int = 2
@export var moon_orbit_factor: float = 0.05
@export var cell_margin: float = 0.2
@export var min_moon_distance_factor: float = 1.8
@export var max_moon_distance_factor: float = 2.5
@export var max_orbit_deviation: float = 0.15

var grid = null
var planet_positions = []
var planet_data = []

# Texture caches
var generated_planet_textures = {}
var generated_moon_textures = {}
var generated_atmosphere_textures = {}

var debug_mode = true

func _ready():
	grid = get_node_or_null("/root/Main/Grid")
	if not grid:
		push_error("ERROR: Grid not found for planet spawning!")
		return
	
	if grid.has_signal("_seed_changed"):
		grid.connect("_seed_changed", _on_grid_seed_changed)

func generate_planets():
	# Clear existing data
	planet_positions.clear()
	planet_data.clear()
	generated_planet_textures.clear()
	generated_moon_textures.clear()
	generated_atmosphere_textures.clear()
	
	if grid.cell_contents.size() == 0:
		return
	
	# Get available cells
	var available_cells = []
	for y in range(1, int(grid.grid_size.y) - 1):
		for x in range(1, int(grid.grid_size.x) - 1):
			if grid.is_boundary_cell(x, y):
				continue
			
			available_cells.append(Vector2i(x, y))
	
	# Track reserved cells
	var reserved_cells = {}
	
	# Calculate planet count
	var non_boundary_count = available_cells.size()
	var planet_count = max(minimum_planets, int(non_boundary_count * planet_percentage / 100.0))
	planet_count = min(planet_count, non_boundary_count)
	
	# Set up RNG
	var rng = RandomNumberGenerator.new()
	rng.seed = grid.seed_value
	
	var actual_planet_count = 0
	
	# Generate planets
	for i in range(planet_count * 3):
		var avail_indices = []
		for j in range(available_cells.size()):
			var pos = available_cells[j]
			if not reserved_cells.has(pos):
				avail_indices.append(j)
		
		if avail_indices.size() == 0:
			break
		
		var idx = avail_indices[rng.randi() % avail_indices.size()]
		var planet_pos = available_cells[idx]
		var x = planet_pos.x
		var y = planet_pos.y
		
		# Mark as planet
		grid.cell_contents[y][x] = grid.CellContent.PLANET
		actual_planet_count += 1
		
		# Generate planet seed
		var planet_seed = grid.seed_value + x * 10000 + y * 1000
		
		# Calculate world position
		var world_pos = Vector2(
			x * grid.cell_size.x + grid.cell_size.x / 2,
			y * grid.cell_size.y + grid.cell_size.y / 2
		)
		
		# Determine moon count
		var has_moons = rng.randi() % 100 < moon_chance
		var num_moons = rng.randi_range(1, max_moons) if has_moons else 0
		
		# Generate moons
		var moons = []
		if has_moons:
			for m in range(num_moons):
				var moon_seed = planet_seed + m * 100
				var moon_texture = MoonGeneratorClass.get_moon_texture(moon_seed)
				
				# Cache texture
				var moon_key = str(moon_seed)
				generated_moon_textures[moon_key] = moon_texture
				
				# Get moon size
				var moon_generator = MoonGeneratorClass.new()
				var moon_pixel_size = moon_generator.get_moon_size(moon_seed)
				
				# Calculate orbit parameters
				var planet_radius = 128.0
				var moon_radius = moon_pixel_size / 2.0
				var min_distance = planet_radius * min_moon_distance_factor + moon_radius
				var max_distance = planet_radius * max_moon_distance_factor + moon_radius
				var moon_orbit_distance = rng.randf_range(min_distance, max_distance)
				var moon_angle = rng.randf_range(0, TAU)
				var orbit_deviation = rng.randf_range(-max_orbit_deviation, max_orbit_deviation)
				
				moons.append({
					"seed": moon_seed,
					"distance": moon_orbit_distance,
					"angle": moon_angle,
					"scale": 1.0,
					"orbit_speed": rng.randf_range(0.2, 0.5) * moon_orbit_factor,
					"orbit_deviation": orbit_deviation,
					"phase_offset": rng.randf_range(0, TAU),
					"pixel_size": moon_pixel_size
				})
		
		# Generate planet data
		var planet_generator = PlanetGeneratorClass.new()
		var planet_theme = planet_generator.get_planet_theme(planet_seed)
		
		var atmosphere_generator = AtmosphereGeneratorClass.new()
		var atmosphere_data = atmosphere_generator.generate_atmosphere_data(planet_theme, planet_seed)
		
		# Store planet data
		planet_positions.append({
			"position": world_pos,
			"grid_x": x,
			"grid_y": y
		})
		
		planet_data.append({
			"seed": planet_seed,
			"scale": 1.0,
			"pixel_size": 256,
			"moons": moons,
			"name": generate_planet_name(x, y),
			"theme": planet_theme,
			"atmosphere": atmosphere_data
		})
		
		# Reserve cells
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx = x + dx
				var ny = y + dy
				
				if grid.is_valid_position(nx, ny):
					reserved_cells[Vector2i(nx, ny)] = true
		
		if actual_planet_count >= planet_count:
			break
	
	grid.queue_redraw()

func draw_planets(canvas: CanvasItem, loaded_cells: Dictionary):
	var time = Time.get_ticks_msec() / 1000.0
	
	for cell_pos in loaded_cells.keys():
		var x = int(cell_pos.x)
		var y = int(cell_pos.y)
		
		if y >= grid.cell_contents.size() or x >= grid.cell_contents[y].size() or grid.cell_contents[y][x] != grid.CellContent.PLANET:
			continue
		
		# Find planet data
		var planet_index = -1
		for i in range(planet_positions.size()):
			if planet_positions[i].grid_x == x and planet_positions[i].grid_y == y:
				planet_index = i
				break
		
		if planet_index != -1:
			var planet = planet_data[planet_index]
			var planet_seed = planet.seed
			
			# Get or generate planet texture
			var planet_key = str(planet_seed)
			var planet_textures = null
			
			if generated_planet_textures.has(planet_key):
				planet_textures = generated_planet_textures[planet_key]
			else:
				planet_textures = PlanetGeneratorClass.get_planet_texture(planet_seed)
				generated_planet_textures[planet_key] = planet_textures
			
			# Get or generate atmosphere texture
			var atmosphere_texture = null
			if generated_atmosphere_textures.has(planet_key):
				atmosphere_texture = generated_atmosphere_textures[planet_key]
			else:
				var atmosphere_generator = AtmosphereGeneratorClass.new()
				atmosphere_texture = atmosphere_generator.generate_atmosphere_texture(
					planet.theme, 
					planet_seed,
					planet.atmosphere.color,
					planet.atmosphere.thickness
				)
				generated_atmosphere_textures[planet_key] = atmosphere_texture
			
			var planet_texture = planet_textures[0]
			var planet_size = Vector2(256, 256)
			
			# Reset transform
			canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			
			# Draw atmosphere
			if atmosphere_texture:
				canvas.draw_set_transform(planet_positions[planet_index].position, 0, Vector2.ONE)
				canvas.draw_texture(atmosphere_texture, -Vector2(atmosphere_texture.get_width(), atmosphere_texture.get_height()) / 2, Color.WHITE)
				canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			
			# Draw planet
			canvas.draw_set_transform(planet_positions[planet_index].position, 0, Vector2.ONE)
			canvas.draw_texture(planet_texture, -planet_size / 2, Color.WHITE)
			canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			
			# Draw moons that should appear behind the planet
			if planet.has("moons"):
				for moon in planet.moons:
					var moon_angle = moon.angle + time * moon.orbit_speed + moon.phase_offset
					var deviation_factor = sin(moon_angle) * moon.orbit_deviation
					
					var moon_pos = planet_positions[planet_index].position + Vector2(
						cos(moon_angle) * moon.distance,
						sin(moon_angle) * moon.distance * (1.0 + deviation_factor)
					)
					
					# Draw moons behind planet
					if sin(moon_angle) > 0:
						draw_procedural_moon(canvas, moon, moon_pos)
				
				# Draw moons in front of planet
				for moon in planet.moons:
					var moon_angle = moon.angle + time * moon.orbit_speed + moon.phase_offset
					var deviation_factor = sin(moon_angle) * moon.orbit_deviation
					
					var moon_pos = planet_positions[planet_index].position + Vector2(
						cos(moon_angle) * moon.distance,
						sin(moon_angle) * moon.distance * (1.0 + deviation_factor)
					)
					
					# Draw moons in front of planet
					if sin(moon_angle) <= 0:
						draw_procedural_moon(canvas, moon, moon_pos)

func draw_procedural_moon(canvas: CanvasItem, moon, moon_pos: Vector2):
	var moon_key = str(moon.seed)
	var moon_texture = null
	
	if generated_moon_textures.has(moon_key):
		moon_texture = generated_moon_textures[moon_key]
	else:
		moon_texture = MoonGeneratorClass.get_moon_texture(moon.seed)
		generated_moon_textures[moon_key] = moon_texture
	
	if moon_texture:
		var moon_size = Vector2(moon.pixel_size, moon.pixel_size)
		
		canvas.draw_set_transform(moon_pos, 0, Vector2.ONE)
		canvas.draw_texture(moon_texture, -moon_size / 2, Color.WHITE)
		canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	else:
		var moon_radius = moon.pixel_size / 2.0
		canvas.draw_circle(moon_pos, moon_radius, Color(0.9, 0.9, 0.9))

func get_all_planet_positions():
	return planet_positions

func reset_planets():
	call_deferred("generate_planets")

func _on_grid_seed_changed(_new_seed = null):
	call_deferred("reset_planets")

func generate_planet_name(x, y):
	var consonants = ["b", "c", "d", "f", "g", "h", "j", "k", "l", "m", "n", "p", "r", "s", "t", "v", "z"]
	var vowels = ["a", "e", "i", "o", "u"]
	
	var rng = RandomNumberGenerator.new()
	rng.seed = grid.seed_value + (x * 100) + y
	
	var planet_name = ""

	# First syllable
	planet_name += consonants[rng.randi() % consonants.size()].to_upper()
	planet_name += vowels[rng.randi() % vowels.size()]

	# Second syllable
	planet_name += consonants[rng.randi() % consonants.size()]
	planet_name += vowels[rng.randi() % vowels.size()]

	# Add a number or hyphen with additional characters
	if rng.randi() % 2 == 0:
		planet_name += "-"
		planet_name += consonants[rng.randi() % consonants.size()].to_upper()
		planet_name += vowels[rng.randi() % vowels.size()]
	else:
		planet_name += " " + str((x + y) % 9 + 1)

	return planet_name

func get_planet_name(x, y):
	for i in range(planet_positions.size()):
		if planet_positions[i].grid_x == x and planet_positions[i].grid_y == y:
			return planet_data[i].name
	
	return generate_planet_name(x, y)
