extends Node
class_name WorldGenerator

# References
var _seed_value: int = 0
var _rng: RandomNumberGenerator
var _debug_mode: bool = false

# Generators
var _planet_generator = null
var _asteroid_generator = null

func _init(seed_value: int = 0) -> void:
	_seed_value = seed_value
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value
	
	# Create generators
	if ResourceLoader.exists("res://scripts/generators/planet_data_generator.gd"):
		var PlanetDataGenerator = load("res://scripts/generators/planet_data_generator.gd")
		_planet_generator = PlanetDataGenerator.new(_seed_value)
	
	if ResourceLoader.exists("res://scripts/generators/asteroid_data_generator.gd"):
		var AsteroidDataGenerator = load("res://scripts/generators/asteroid_data_generator.gd")
		_asteroid_generator = AsteroidDataGenerator.new(_seed_value)

func generate_world_data(seed_value: int) -> WorldData:
	_seed_value = seed_value
	_rng.seed = seed_value
	
	# Create a new world data object
	var world_data = WorldData.new(seed_value)
	
	# Generate planets, asteroid fields, etc.
	_generate_celestial_bodies(world_data)
	
	return world_data

func _generate_celestial_bodies(world_data: WorldData) -> void:
	# Keep track of occupied cells to avoid overlaps
	var occupied_cells = {}
	
	# Set up default grid size and cell size
	var grid_size = world_data.grid_size
	var grid_cell_size = world_data.grid_cell_size
	
	# Generate a default player start position in the center
	world_data.player_start_cell = Vector2i(grid_size / 2, grid_size / 2)
	world_data.player_start_position = _cell_to_world(world_data.player_start_cell, grid_size, grid_cell_size)
	
	# Generate terran planets
	var num_terran_planets = 3 + _rng.randi() % 3  # 3-5 planets
	for i in range(num_terran_planets):
		var cell = _find_unoccupied_cell(occupied_cells, grid_size)
		if cell != Vector2i(-1, -1):
			var planet_data = _generate_planet(cell, false, -1, world_data)
			world_data.add_planet(planet_data)
			occupied_cells[cell] = true
	
	# Generate gaseous planets
	var num_gaseous_planets = 1 + _rng.randi() % 2  # 1-2 planets
	for i in range(num_gaseous_planets):
		var cell = _find_unoccupied_cell(occupied_cells, grid_size)
		if cell != Vector2i(-1, -1):
			var planet_data = _generate_planet(cell, true, -1, world_data)
			world_data.add_planet(planet_data)
			occupied_cells[cell] = true
	
	# Generate asteroid fields
	var num_asteroid_fields = 2 + _rng.randi() % 3  # 2-4 fields
	for i in range(num_asteroid_fields):
		var cell = _find_unoccupied_cell(occupied_cells, grid_size)
		if cell != Vector2i(-1, -1):
			var field_data = _generate_asteroid_field(cell, world_data)
			world_data.add_asteroid_field(field_data)
			occupied_cells[cell] = true

func _generate_planet(cell: Vector2i, is_gaseous: bool, theme_id: int, world_data: WorldData) -> PlanetData:
	# Get a deterministic entity ID
	var entity_id = _get_deterministic_entity_id(cell)
	
	# Calculate world position from cell
	var position = _cell_to_world(cell, world_data.grid_size, world_data.grid_cell_size)
	
	# Get deterministic seed for this planet
	var planet_seed = _seed_value + (cell.x * 1000) + (cell.y * 100)
	
	# Create planet data 
	var planet_data
	
	if _planet_generator:
		# Use planet generator if available
		planet_data = _planet_generator.generate_planet(entity_id, position, planet_seed, theme_id, false)
		
		# Override gaseous flag if specified
		if is_gaseous != planet_data.is_gaseous:
			planet_data.is_gaseous = is_gaseous
			planet_data.planet_category = PlanetData.PlanetCategory.GASEOUS if is_gaseous else PlanetData.PlanetCategory.TERRAN
	else:
		# Fallback: Create basic planet data
		planet_data = PlanetData.new(entity_id, position, planet_seed)
		planet_data.is_gaseous = is_gaseous
		planet_data.planet_category = PlanetData.PlanetCategory.GASEOUS if is_gaseous else PlanetData.PlanetCategory.TERRAN
		
		# Basic properties
		planet_data.planet_name = _generate_planet_name(planet_seed, is_gaseous)
		planet_data.pixel_size = 256 if not is_gaseous else 512
		
		# Random theme ID if not specified
		if theme_id < 0:
			if is_gaseous:
				planet_data.planet_theme = 7 + _rng.randi() % 4  # 7-10 (Jupiter to Neptune)
			else:
				planet_data.planet_theme = _rng.randi() % 7  # 0-6 (Arid to Ocean)
		else:
			planet_data.planet_theme = theme_id
		
		# Generate 0-2 moons for terran, 2-4 for gaseous
		var moon_count = _rng.randi_range(0 if not is_gaseous else 2, 2 if not is_gaseous else 4) 
		_generate_moons_for_planet(planet_data, moon_count)
	
	# Set grid cell
	planet_data.grid_cell = cell
	
	return planet_data

func _generate_asteroid_field(cell: Vector2i, world_data: WorldData) -> AsteroidFieldData:
	# Get a deterministic entity ID
	var entity_id = _get_deterministic_entity_id(cell)
	
	# Calculate world position from cell
	var position = _cell_to_world(cell, world_data.grid_size, world_data.grid_cell_size)
	
	# Get deterministic seed
	var field_seed = _seed_value + (cell.x * 1000) + (cell.y * 100) + 5000
	
	# Create asteroid field data
	var field_data
	
	if _asteroid_generator:
		# Use asteroid generator if available
		field_data = _asteroid_generator.generate_asteroid_field(entity_id, position, field_seed)
	else:
		# Fallback: Create basic asteroid field
		field_data = AsteroidFieldData.new(entity_id, position, field_seed)
		field_data.field_radius = 400.0 * _rng.randf_range(0.8, 1.2)
		field_data.min_asteroids = 8 + _rng.randi() % 5  # 8-12
		field_data.max_asteroids = field_data.min_asteroids + 5 + _rng.randi() % 5  # min + 5-9
	
	# Set grid cell
	field_data.grid_cell = cell
	
	# Populate with asteroids
	if _asteroid_generator:
		_asteroid_generator.populate_asteroid_field(field_data, world_data)
	else:
		# Basic asteroid generation
		_generate_basic_asteroids(field_data)
	
	return field_data

func _generate_moons_for_planet(planet_data: PlanetData, moon_count: int) -> void:
	var planet_radius = planet_data.pixel_size / 2.0
	
	for i in range(moon_count):
		var moon_id = planet_data.entity_id * 100 + i + 1
		var moon_seed = planet_data.seed_value + 10000 + i * 100
		_rng.seed = moon_seed
		
		# Create moon data
		var moon_data = MoonData.new(moon_id, planet_data.position, moon_seed, _get_random_moon_type())
		
		# Set parent planet ID
		moon_data.parent_planet_id = planet_data.entity_id
		
		# Configure orbit
		var distance = planet_radius * _rng.randf_range(1.8, 3.0) * (1.0 + 0.2 * i)
		var base_angle = _rng.randf() * TAU
		var orbit_speed = _rng.randf_range(0.02, 0.1) / (1.0 + 0.2 * i)
		var orbit_deviation = _rng.randf_range(0.0, 0.1)
		var phase_offset = _rng.randf() * TAU
		
		moon_data.distance = distance
		moon_data.base_angle = base_angle
		moon_data.orbit_speed = orbit_speed
		moon_data.orbit_deviation = orbit_deviation
		moon_data.phase_offset = phase_offset
		
		# Add to planet
		planet_data.add_moon(moon_data)

func _generate_basic_asteroids(field_data: AsteroidFieldData) -> void:
	# Determine asteroid count
	var asteroid_count = _rng.randi_range(field_data.min_asteroids, field_data.max_asteroids)
	
	# Get positions based on field parameters
	var positions = field_data.calculate_spawn_positions()
	
	# If no positions calculated, generate some basic ones
	if positions.is_empty():
		for i in range(asteroid_count):
			var angle = _rng.randf() * TAU
			var distance = _rng.randf() * field_data.field_radius
			var size_category = AsteroidData.SizeCategory.MEDIUM
			
			# Determine size category
			var size_roll = _rng.randf()
			if size_roll < field_data.small_asteroid_chance:
				size_category = AsteroidData.SizeCategory.SMALL
			elif size_roll < field_data.small_asteroid_chance + field_data.medium_asteroid_chance:
				size_category = AsteroidData.SizeCategory.MEDIUM
			else:
				size_category = AsteroidData.SizeCategory.LARGE
				
			var pos = Vector2(cos(angle), sin(angle)) * distance
			
			positions.append({
				"position": pos,
				"size": size_category,
				"scale": _get_scale_for_size(size_category) * _rng.randf_range(0.9, 1.1),
				"rotation_speed": _rng.randf_range(-field_data.max_rotation_speed, field_data.max_rotation_speed),
				"velocity": Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(field_data.min_linear_speed, field_data.max_linear_speed),
				"variant": _rng.randi() % 4
			})
	
	# Create asteroid data from positions
	for pos_data in positions:
		var asteroid_id = field_data.entity_id * 1000 + field_data.asteroids.size() + 1
		var asteroid_seed = field_data.seed_value + field_data.asteroids.size() * 100
		
		var asteroid = AsteroidData.new(
			asteroid_id,
			field_data.position + pos_data.position,
			asteroid_seed,
			pos_data.size
		)
		
		# Apply position-specific attributes
		asteroid.scale_factor = pos_data.scale
		asteroid.rotation_speed = pos_data.rotation_speed
		asteroid.linear_velocity = pos_data.velocity
		asteroid.variant = pos_data.variant
		
		# Set field association
		asteroid.field_id = field_data.entity_id
		
		# Add to field
		field_data.add_asteroid(asteroid)

# HELPER METHODS

func _get_deterministic_entity_id(cell: Vector2i) -> int:
	# Use a formula that ensures unique IDs for each cell
	return 1000 + (cell.x * 100) + cell.y

func _cell_to_world(cell: Vector2i, grid_size: int, cell_size: int) -> Vector2:
	var grid_offset = Vector2(cell_size * grid_size / 2.0, cell_size * grid_size / 2.0)
	return Vector2(
		cell.x * cell_size + cell_size / 2.0,
		cell.y * cell_size + cell_size / 2.0
	) - grid_offset

func _find_unoccupied_cell(occupied_cells: Dictionary, grid_size: int) -> Vector2i:
	# Try random cells first for a limited number of attempts
	for attempt in range(10):
		var cell = Vector2i(_rng.randi() % grid_size, _rng.randi() % grid_size)
		if not occupied_cells.has(cell):
			return cell
	
	# If random attempts fail, try all cells systematically
	for x in range(grid_size):
		for y in range(grid_size):
			var cell = Vector2i(x, y)
			if not occupied_cells.has(cell):
				return cell
	
	# No cell found
	return Vector2i(-1, -1)

func _get_random_moon_type() -> int:
	var roll = _rng.randf()
	if roll < 0.5:
		return MoonData.MoonType.ROCKY
	elif roll < 0.8:
		return MoonData.MoonType.ICY
	else:
		return MoonData.MoonType.VOLCANIC

func _get_scale_for_size(size_category: int) -> float:
	match size_category:
		AsteroidData.SizeCategory.SMALL: return 0.5
		AsteroidData.SizeCategory.MEDIUM: return 1.0
		AsteroidData.SizeCategory.LARGE: return 1.5
		_: return 1.0

func _generate_planet_name(seed_value: int, is_gaseous: bool) -> String:
	_rng.seed = seed_value + 12345
	
	var prefixes = [
		"Alpha", "Beta", "Gamma", "Delta", "Epsilon",
		"Nova", "Proxima", "Tau", "Omega", "Sigma"
	]
	
	var planet_types = [
		"Prime", "Minor", "Major", "Secundus", "Tertius"
	]
	
	var designation = str(_rng.randi_range(1, 999))
	var prefix = prefixes[_rng.randi() % prefixes.size()]
	var type = planet_types[_rng.randi() % planet_types.size()]
	
	return prefix + "-" + designation + " " + type
