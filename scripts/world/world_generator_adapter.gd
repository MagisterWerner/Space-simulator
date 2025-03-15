extends Node
class_name WorldGeneratorAdapter

# This class adapts the current WorldGenerator to output WorldData objects
# This is a transitional class for Phase 1 of the refactoring

# Signals
signal world_data_generated(world_data)

# References to existing systems
var world_generator: WorldGenerator = null
var game_settings: GameSettings = null
var seed_manager = null
var entity_id_counter: int = 0

# Debug mode
var debug_mode: bool = false

func _ready() -> void:
	# Find or create the world generator
	_find_world_generator()
	
	# Find game settings
	_find_game_settings()
	
	# Connect to SeedManager
	if has_node("/root/SeedManager"):
		seed_manager = get_node("/root/SeedManager")

func _find_world_generator() -> void:
	# First check if we already have a reference
	if world_generator != null and is_instance_valid(world_generator):
		return
	
	# Try to find existing world generator in the scene
	world_generator = get_node_or_null("WorldGenerator")
	
	if not world_generator:
		# Look for WorldGenerator in the main scene
		var main = get_tree().current_scene
		world_generator = main.get_node_or_null("WorldGenerator")
	
	if not world_generator:
		# Create a new one if needed
		world_generator = WorldGenerator.new()
		add_child(world_generator)
		
		# Connect to essential signals
		if world_generator.has_signal("world_generation_completed"):
			world_generator.connect("world_generation_completed", _on_world_generation_completed)
			
		if world_generator.has_signal("entity_generated"):
			world_generator.connect("entity_generated", _on_entity_generated)

func _find_game_settings() -> void:
	# First check if we already have a reference
	if game_settings != null:
		return
	
	# Look in the main scene
	var main = get_tree().current_scene
	game_settings = main.get_node_or_null("GameSettings")
	
	if game_settings:
		debug_mode = game_settings.debug_mode and game_settings.debug_world_generator
		
		# Connect to debug settings changes
		if game_settings.has_signal("debug_settings_changed"):
			game_settings.connect("debug_settings_changed", _on_debug_settings_changed)

func _on_debug_settings_changed(debug_settings: Dictionary) -> void:
	debug_mode = debug_settings.get("master", false) and debug_settings.get("world_generator", false)

# Generate world data using the current world generator
func generate_world_data() -> WorldData:
	# Create world data container
	var world_data = WorldData.new()
	
	# Set basic properties
	world_data.seed_value = game_settings.get_seed() if game_settings else 0
	world_data.seed_hash = game_settings.seed_hash if game_settings else ""
	world_data.grid_size = game_settings.grid_size if game_settings else 10
	world_data.grid_cell_size = game_settings.grid_cell_size if game_settings else 1024
	
	# Record start time for performance tracking
	var start_time = Time.get_ticks_msec()
	
	# Generate the world using existing generator
	var result = world_generator.generate_starter_world()
	
	# Store player start information
	world_data.player_start_cell = result.player_planet_cell
	world_data.player_start_position = game_settings.get_cell_world_position(result.player_planet_cell) if game_settings else Vector2.ZERO
	
	# Generate entity data from existing entities
	_convert_existing_entities_to_data(world_data)
	
	# Record generation time
	world_data.generation_time_ms = Time.get_ticks_msec() - start_time
	
	# Emit signal
	world_data_generated.emit(world_data)
	
	if debug_mode:
		print("WorldGeneratorAdapter: Generated world data with %d entities in %d ms" % [
			world_data.entities.size(),
			world_data.generation_time_ms
		])
	
	return world_data

# Convert existing entities to data objects
func _convert_existing_entities_to_data(world_data: WorldData) -> void:
	# Get entity counts from world generator
	var terran_count = world_generator.get_entity_count(WorldGenerator.ENTITY_TYPES.TERRAN_PLANET)
	var gaseous_count = world_generator.get_entity_count(WorldGenerator.ENTITY_TYPES.GASEOUS_PLANET)
	var asteroid_count = world_generator.get_entity_count(WorldGenerator.ENTITY_TYPES.ASTEROID_FIELD)
	var station_count = world_generator.get_entity_count(WorldGenerator.ENTITY_TYPES.STATION)
	
	if debug_mode:
		print("WorldGeneratorAdapter: Converting %d terran planets, %d gaseous planets, %d asteroid fields, %d stations" % [
			terran_count, gaseous_count, asteroid_count, station_count
		])
	
	# Fetch all grid cells with entities
	for cell in world_generator._generated_entities.keys():
		var cell_data = world_generator._generated_entities[cell]
		
		for entity_type in cell_data:
			for entity in cell_data[entity_type]:
				if is_instance_valid(entity):
					# Convert entity to data
					var entity_data = _convert_entity_to_data(entity, entity_type, cell)
					
					if entity_data:
						world_data.add_entity(entity_data)

# Convert a specific entity to its data representation
func _convert_entity_to_data(entity: Node, entity_type: String, cell: Vector2i) -> EntityData:
	entity_id_counter += 1
	
	match entity_type:
		"planet_spawner":
			return _convert_planet_to_data(entity, cell)
			
		"asteroid_field":
			return _convert_asteroid_field_to_data(entity, cell)
			
		"station":
			return _convert_station_to_data(entity, cell)
			
	return null

# Convert a planet to planet data
func _convert_planet_to_data(planet_spawner: Node, cell: Vector2i) -> PlanetData:
	# Get the actual planet instance
	var planet_instance = null
	if planet_spawner.has_method("get_planet_instance"):
		planet_instance = planet_spawner.get_planet_instance()
	
	if not planet_instance:
		return null
	
	var planet_data = PlanetData.new()
	planet_data.entity_id = entity_id_counter
	planet_data.seed_value = planet_spawner.local_seed_offset
	planet_data.grid_cell = cell
	planet_data.world_position = planet_instance.global_position
	planet_data.entity_type = "planet"
	
	# Determine if it's a terran or gaseous planet
	if planet_spawner.is_gaseous_planet():
		planet_data.planet_category = PlanetData.PlanetCategory.GASEOUS
		
		# Get gas giant type
		if planet_spawner.has_method("get_gas_giant_type_name"):
			var type_name = planet_spawner.get_gas_giant_type_name()
			match type_name:
				"Jupiter-like": 
					planet_data.planet_theme = PlanetData.PlanetTheme.JUPITER
				"Saturn-like": 
					planet_data.planet_theme = PlanetData.PlanetTheme.SATURN
				"Uranus-like": 
					planet_data.planet_theme = PlanetData.PlanetTheme.URANUS
				"Neptune-like": 
					planet_data.planet_theme = PlanetData.PlanetTheme.NEPTUNE
	else:
		planet_data.planet_category = PlanetData.PlanetCategory.TERRAN
		
		# Get terran theme
		if planet_instance.has_method("get_theme_name"):
			var theme_name = planet_instance.get_theme_name()
			match theme_name.to_lower():
				"arid": 
					planet_data.planet_theme = PlanetData.PlanetTheme.ARID
				"ice": 
					planet_data.planet_theme = PlanetData.PlanetTheme.ICE
				"lava": 
					planet_data.planet_theme = PlanetData.PlanetTheme.LAVA
				"lush": 
					planet_data.planet_theme = PlanetData.PlanetTheme.LUSH
				"desert": 
					planet_data.planet_theme = PlanetData.PlanetTheme.DESERT
				"alpine": 
					planet_data.planet_theme = PlanetData.PlanetTheme.ALPINE
				"ocean": 
					planet_data.planet_theme = PlanetData.PlanetTheme.OCEAN
	
	# Get pixel size
	if planet_instance.has_variable("pixel_size"):
		planet_data.pixel_size = planet_instance.pixel_size
	
	# Get name
	if planet_instance.has_variable("planet_name"):
		planet_data.entity_name = planet_instance.planet_name
	
	# Check if this is player starting planet
	planet_data.is_player_starting_planet = (
		cell == world_generator.player_start_cell or
		planet_instance.global_position == world_generator.player_start_position
	)
	
	# Process moons if any
	if planet_instance.has_variable("moons") and not planet_instance.moons.is_empty():
		for moon in planet_instance.moons:
			if is_instance_valid(moon):
				var moon_data = _convert_moon_to_data(moon, planet_data)
				if moon_data:
					planet_data.moons.append(moon_data)
		
		planet_data.moon_count = planet_data.moons.size()
	
	return planet_data

# Convert a moon to moon data
func _convert_moon_to_data(moon: Node, parent_planet: PlanetData) -> MoonData:
	entity_id_counter += 1
	
	var moon_data = MoonData.new()
	moon_data.entity_id = entity_id_counter
	moon_data.entity_type = "moon"
	moon_data.parent_planet_id = parent_planet.entity_id
	moon_data.world_position = moon.global_position
	moon_data.grid_cell = parent_planet.grid_cell  # Moons share cell with parent
	
	# Get seed value
	if moon.has_variable("seed_value"):
		moon_data.seed_value = moon.seed_value
	
	# Get moon type
	if moon is MoonBase or moon.has_method("_get_moon_type_prefix"):
		var prefix = moon._get_moon_type_prefix()
		match prefix:
			"Rocky": 
				moon_data.moon_type = MoonData.MoonType.ROCKY
			"Icy": 
				moon_data.moon_type = MoonData.MoonType.ICY
			"Volcanic": 
				moon_data.moon_type = MoonData.MoonType.VOLCANIC
	
	# Get orbit parameters
	if moon.has_variable("distance"):
		moon_data.orbit_distance = moon.distance
	if moon.has_variable("orbit_speed"):
		moon_data.orbit_speed = moon.orbit_speed
	if moon.has_variable("orbit_deviation"):
		moon_data.orbit_deviation = moon.orbit_deviation
	if moon.has_variable("base_angle"):
		moon_data.base_angle = moon.base_angle
	if moon.has_variable("phase_offset"):
		moon_data.phase_offset = moon.phase_offset
	if moon.has_variable("orbital_inclination"):
		moon_data.orbital_inclination = moon.orbital_inclination
	if moon.has_variable("orbit_vertical_offset"):
		moon_data.orbit_vertical_offset = moon.orbit_vertical_offset
	
	# Get visual parameters
	if moon.has_variable("orbit_color"):
		moon_data.orbit_color = moon.orbit_color
	if moon.has_variable("is_gaseous"):
		moon_data.is_gaseous = moon.is_gaseous
	if moon.has_variable("pixel_size"):
		moon_data.pixel_size = moon.pixel_size
	if moon.has_variable("moon_name"):
		moon_data.entity_name = moon.moon_name
	
	return moon_data

# Convert an asteroid field to asteroid field data
func _convert_asteroid_field_to_data(field: Node, cell: Vector2i) -> AsteroidFieldData:
	var field_data = AsteroidFieldData.new()
	field_data.entity_id = entity_id_counter
	field_data.seed_value = field.local_seed_offset if field.has_variable("local_seed_offset") else 0
	field_data.grid_cell = cell
	field_data.world_position = field.global_position
	
	# Get field properties
	if field.has_variable("field_radius"):
		field_data.field_radius = field.field_radius
	if field.has_variable("min_asteroids"):
		field_data.min_asteroids = field.min_asteroids
	if field.has_variable("max_asteroids"):
		field_data.max_asteroids = field.max_asteroids
	if field.has_variable("min_distance_between"):
		field_data.min_distance_between = field.min_distance_between
	if field.has_variable("size_variation"):
		field_data.size_variation = field.size_variation
	
	# Get distribution probabilities
	if field.has_variable("small_asteroid_chance"):
		field_data.small_asteroid_chance = field.small_asteroid_chance
	if field.has_variable("medium_asteroid_chance"):
		field_data.medium_asteroid_chance = field.medium_asteroid_chance
	if field.has_variable("large_asteroid_chance"):
		field_data.large_asteroid_chance = field.large_asteroid_chance
	
	# Get physics parameters
	if field.has_variable("min_linear_speed"):
		field_data.min_linear_speed = field.min_linear_speed
	if field.has_variable("max_linear_speed"):
		field_data.max_linear_speed = field.max_linear_speed
	if field.has_variable("max_rotation_speed"):
		field_data.max_rotation_speed = field.max_rotation_speed
	
	# Get number of asteroids
	if field.has_method("get_asteroid_count"):
		field_data.asteroid_count = field.get_asteroid_count()
	
	return field_data

# Convert a station to station data
func _convert_station_to_data(station: Node, cell: Vector2i) -> StationData:
	var station_data = StationData.new()
	station_data.entity_id = entity_id_counter
	station_data.grid_cell = cell
	station_data.world_position = station.global_position
	
	# Get seed value for deterministic generation
	if station.has_variable("seed_value"):
		station_data.seed_value = station.seed_value
	else:
		# Create a deterministic seed from cell coordinates
		station_data.seed_value = cell.x * 10000 + cell.y * 100 + randi() % 100
	
	# Get station type
	if station.has_variable("station_type"):
		station_data.station_type = station.station_type
	else:
		# Assign a random type
		var rng = RandomNumberGenerator.new()
		rng.seed = station_data.seed_value
		station_data.station_type = rng.randi() % StationData.StationType.size()
	
	# Get station name
	if station.has_variable("station_name"):
		station_data.entity_name = station.station_name
	else:
		# Generate a default name
		station_data.entity_name = "Station " + str(station_data.seed_value % 1000)
	
	# Get resources if available
	if station.has_variable("available_resources"):
		station_data.available_resources = station.available_resources.duplicate()
	if station.has_variable("resource_prices"):
		station_data.resource_prices = station.resource_prices.duplicate()
	if station.has_variable("resource_quantities"):
		station_data.resource_quantities = station.resource_quantities.duplicate()
	
	return station_data

# Event handlers
func _on_world_generation_completed() -> void:
	if debug_mode:
		print("WorldGeneratorAdapter: World generation completed, creating world data")
	
	# Create world data after generation is complete
	generate_world_data()

func _on_entity_generated(entity, type, cell) -> void:
	if debug_mode:
		print("WorldGeneratorAdapter: Entity generated - type: %s, cell: %s" % [type, cell])
		
	# Entity tracking happens automatically in the existing world generator
