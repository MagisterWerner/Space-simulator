extends Node

signal entity_spawned(entity, entity_type)
signal entity_despawned(entity, entity_type)
signal player_spawned(player)

# Consolidated entity storage
var entities = {
	"player": {},
	"ship": {},
	"asteroid": {},
	"asteroid_field": {},
	"planet": {},
	"moon": {},
	"station": {}
}

# Entity counter for generating unique IDs
var entity_counter = 0

# Entity scenes
var player_ship_scene = null
var enemy_ship_scenes = []
var asteroid_scenes = []
var station_scenes = []
var planet_scenes = {}  # By planet type
var moon_scenes = {}    # By moon type

# Initialization flag
var _scenes_initialized = false

# Entity data mapping (entity -> EntityData)
var _entity_data_map = {}

# Debug mode
var _debug_mode = false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Check for debug mode
	var main_scene = get_tree().current_scene
	var game_settings = main_scene.get_node_or_null("GameSettings")
	if game_settings:
		_debug_mode = game_settings.debug_mode
		
	call_deferred("_initialize_scenes")

func _initialize_scenes():
	if _scenes_initialized: 
		return
	
	# Load player ship scene
	player_ship_scene = load("res://scenes/player/player_ship.tscn")
	
	# Load planet scenes
	_load_planet_scenes()
	
	# Load asteroid scenes
	_load_asteroid_scenes()
	
	# Load station scenes
	_load_station_scenes()
	
	_scenes_initialized = true
	
	if _debug_mode:
		print("EntityManager: Scenes initialized")

# Load available planet scenes
func _load_planet_scenes():
	# Try to load terran and gaseous planet scenes
	var terran_path = "res://scenes/world/planet_terran.tscn"
	var gaseous_path = "res://scenes/world/planet_gaseous.tscn"
	
	if ResourceLoader.exists(terran_path):
		planet_scenes["terran"] = load(terran_path)
	
	if ResourceLoader.exists(gaseous_path):
		planet_scenes["gaseous"] = load(gaseous_path)
	
	# Load moon scenes
	var moon_base_path = "res://scenes/world/moon_base.tscn"
	var moon_rocky_path = "res://scenes/world/moon_rocky.tscn"
	var moon_icy_path = "res://scenes/world/moon_icy.tscn"
	var moon_volcanic_path = "res://scenes/world/moon_volcanic.tscn"
	
	if ResourceLoader.exists(moon_base_path):
		moon_scenes["base"] = load(moon_base_path)
	
	if ResourceLoader.exists(moon_rocky_path):
		moon_scenes["rocky"] = load(moon_rocky_path)
	
	if ResourceLoader.exists(moon_icy_path):
		moon_scenes["icy"] = load(moon_icy_path)
	
	if ResourceLoader.exists(moon_volcanic_path):
		moon_scenes["volcanic"] = load(moon_volcanic_path)

# Load available asteroid scenes
func _load_asteroid_scenes():
	var asteroid_path = "res://scenes/entities/asteroid.tscn"
	var asteroid_field_path = "res://scenes/world/asteroid_field.tscn"
	
	if ResourceLoader.exists(asteroid_path):
		asteroid_scenes.append(load(asteroid_path))
	
	if ResourceLoader.exists(asteroid_field_path):
		asteroid_scenes.append(load(asteroid_field_path))

# Load available station scenes
func _load_station_scenes():
	var station_path = "res://scenes/world/station.tscn"
	var trading_station_path = "res://scenes/world/trading_station.tscn"
	var military_station_path = "res://scenes/world/military_station.tscn"
	var research_station_path = "res://scenes/world/research_station.tscn"
	var mining_station_path = "res://scenes/world/mining_station.tscn"
	
	if ResourceLoader.exists(station_path):
		station_scenes.append(load(station_path))
	
	if ResourceLoader.exists(trading_station_path):
		station_scenes.append(load(trading_station_path))
		
	if ResourceLoader.exists(military_station_path):
		station_scenes.append(load(military_station_path))
		
	if ResourceLoader.exists(research_station_path):
		station_scenes.append(load(research_station_path))
		
	if ResourceLoader.exists(mining_station_path):
		station_scenes.append(load(mining_station_path))

# Register an entity with the manager
func register_entity(entity, entity_type = "generic"):
	# Generate a unique ID for the entity
	entity_counter += 1
	var entity_id = entity_counter
	
	# Create type dictionary if it doesn't exist
	if not entities.has(entity_type):
		entities[entity_type] = {}
	
	# Store the entity
	entities[entity_type][entity_id] = entity
	
	# Set up entity metadata
	entity.set_meta("entity_id", entity_id)
	entity.set_meta("entity_type", entity_type)
	
	# Connect to tree_exiting signal to automatically deregister
	if not entity.tree_exiting.is_connected(_on_entity_tree_exiting):
		entity.tree_exiting.connect(_on_entity_tree_exiting.bind(entity))
	
	# Special handling for player entities
	if entity_type == "player":
		player_spawned.emit(entity)
	
	entity_spawned.emit(entity, entity_type)
	return entity_id

# Register entity with associated data
func register_entity_with_data(entity, entity_data):
	var entity_type = "generic"
	var entity_id = 0
	
	if entity_data:
		entity_type = entity_data.entity_type
		entity_id = entity_data.entity_id
		
		# Store the data mapping
		_entity_data_map[entity] = entity_data
	
	# Register the entity (will generate ID if not provided)
	if entity_id <= 0:
		entity_id = register_entity(entity, entity_type)
	else:
		# Use the existing ID from the data
		# Create type dictionary if it doesn't exist
		if not entities.has(entity_type):
			entities[entity_type] = {}
		
		# Store the entity
		entities[entity_type][entity_id] = entity
		
		# Set up entity metadata
		entity.set_meta("entity_id", entity_id)
		entity.set_meta("entity_type", entity_type)
		
		# Connect to tree_exiting signal to automatically deregister
		if not entity.tree_exiting.is_connected(_on_entity_tree_exiting):
			entity.tree_exiting.connect(_on_entity_tree_exiting.bind(entity))
		
		# Special handling for player entities
		if entity_type == "player":
			player_spawned.emit(entity)
		
		entity_spawned.emit(entity, entity_type)
	
	return entity_id

# Deregister an entity
func deregister_entity(entity):
	if not entity.has_meta("entity_id") or not entity.has_meta("entity_type"):
		return
	
	var entity_id = entity.get_meta("entity_id")
	var entity_type = entity.get_meta("entity_type")
	
	# Remove from the dictionary if it exists
	if entities.has(entity_type) and entities[entity_type].has(entity_id):
		entities[entity_type].erase(entity_id)
	
	# Remove from data mapping
	if _entity_data_map.has(entity):
		_entity_data_map.erase(entity)
	
	entity_despawned.emit(entity, entity_type)

# Handle entity tree exiting event
func _on_entity_tree_exiting(entity):
	deregister_entity(entity)

# --- Spawning Methods ---

# Spawn player at specified position
func spawn_player(spawn_position = Vector2.ZERO):
	_initialize_scenes()
	
	if not player_ship_scene:
		push_error("EntityManager: player_ship_scene not set")
		return null
	
	var player = player_ship_scene.instantiate()
	add_child(player)
	player.global_position = spawn_position
	register_entity(player, "player")
	
	return player

# Spawn an entity from data
func spawn_entity_from_data(entity_data, parent_node = null):
	_initialize_scenes()
	
	if entity_data is PlanetData:
		return spawn_planet_from_data(entity_data, parent_node)
	elif entity_data is MoonData:
		return spawn_moon_from_data(entity_data, parent_node)
	elif entity_data is AsteroidData:
		return spawn_asteroid_from_data(entity_data, parent_node)
	elif entity_data is AsteroidFieldData:
		return spawn_asteroid_field_from_data(entity_data, parent_node)
	elif entity_data is StationData:
		return spawn_station_from_data(entity_data, parent_node)
	else:
		push_error("EntityManager: Unknown entity data type")
		return null

# Spawn planet from data
func spawn_planet_from_data(planet_data, parent_node = null):
	# Determine planet scene
	var planet_scene = null
	if planet_data.is_gaseous:
		planet_scene = planet_scenes.get("gaseous")
	else:
		planet_scene = planet_scenes.get("terran")
	
	if not planet_scene:
		push_error("EntityManager: No planet scene available for type " + str(planet_data.planet_category))
		return null
	
	# Instantiate the planet
	var planet = planet_scene.instantiate()
	
	# Add to parent or to scene
	if parent_node and is_instance_valid(parent_node):
		parent_node.add_child(planet)
	else:
		add_child(planet)
	
	# Set position
	planet.global_position = planet_data.position
	
	# Configure planet
	if planet.has_method("initialize"):
		var params = {
			"seed_value": planet_data.seed_value,
			"theme_override": planet_data.planet_theme,
			"category_override": planet_data.planet_category,
			"use_texture_cache": true
		}
		
		if planet_data.grid_cell != Vector2i(-1, -1):
			params["grid_x"] = planet_data.grid_cell.x
			params["grid_y"] = planet_data.grid_cell.y
		
		planet.initialize(params)
	
	# Set name if available
	if planet_data.planet_name:
		planet.name = planet_data.planet_name
	
	# Register entity with data
	register_entity_with_data(planet, planet_data)
	
	# Spawn any moons
	for moon_data in planet_data.moons:
		spawn_moon_from_data(moon_data, planet)
	
	return planet

# Spawn moon from data
func spawn_moon_from_data(moon_data, parent_planet = null):
	# Get moon scene based on type
	var moon_scene = null
	match moon_data.moon_type:
		MoonData.MoonType.ROCKY:
			moon_scene = moon_scenes.get("rocky", moon_scenes.get("base"))
		MoonData.MoonType.ICY:
			moon_scene = moon_scenes.get("icy", moon_scenes.get("base"))
		MoonData.MoonType.VOLCANIC:
			moon_scene = moon_scenes.get("volcanic", moon_scenes.get("base"))
		_:
			moon_scene = moon_scenes.get("base")
	
	if not moon_scene:
		push_error("EntityManager: No moon scene available")
		return null
	
	# Instantiate the moon
	var moon = moon_scene.instantiate()
	
	# Add to parent planet if provided
	if parent_planet and is_instance_valid(parent_planet):
		parent_planet.add_child(moon)
	else:
		add_child(moon)
	
	# Configure moon
	if moon.has_method("initialize"):
		var params = {
			"seed_value": moon_data.seed_value,
			"parent_planet": parent_planet,
			"distance": moon_data.distance,
			"base_angle": moon_data.base_angle,
			"orbit_speed": moon_data.orbit_speed,
			"orbit_deviation": moon_data.orbit_deviation,
			"phase_offset": moon_data.phase_offset,
			"moon_name": moon_data.moon_name,
			"is_gaseous": moon_data.is_gaseous,
			"moon_type": moon_data.moon_type,
			"orbital_inclination": moon_data.orbital_inclination,
			"orbit_vertical_offset": moon_data.orbit_vertical_offset
		}
		moon.initialize(params)
	
	# Set name if available
	if moon_data.moon_name:
		moon.name = moon_data.moon_name
	
	# Register entity with data
	register_entity_with_data(moon, moon_data)
	
	return moon

# Spawn asteroid from data
func spawn_asteroid_from_data(asteroid_data, parent_node = null):
	if asteroid_scenes.is_empty():
		push_error("EntityManager: No asteroid scene available")
		return null
	
	# Use first asteroid scene
	var asteroid = asteroid_scenes[0].instantiate()
	
	# Add to parent or to scene
	if parent_node and is_instance_valid(parent_node):
		parent_node.add_child(asteroid)
	else:
		add_child(asteroid)
	
	# Set position
	asteroid.global_position = asteroid_data.position
	
	# Convert size category to string
	var size_string = "medium"
	match asteroid_data.size_category:
		AsteroidData.SizeCategory.SMALL: size_string = "small"
		AsteroidData.SizeCategory.MEDIUM: size_string = "medium"
		AsteroidData.SizeCategory.LARGE: size_string = "large"
	
	# Configure asteroid
	if asteroid.has_method("setup"):
		asteroid.setup(
			size_string,
			asteroid_data.variant,
			asteroid_data.scale_factor,
			asteroid_data.rotation_speed,
			asteroid_data.linear_velocity
		)
	
	# Register entity with data
	register_entity_with_data(asteroid, asteroid_data)
	
	return asteroid

# Spawn asteroid field from data
func spawn_asteroid_field_from_data(field_data, parent_node = null):
	if asteroid_scenes.size() < 2:
		# Create a simple Node2D as fallback
		var field = Node2D.new()
		field.name = "AsteroidField_" + str(field_data.entity_id)
		
		# Add to parent or to scene
		if parent_node and is_instance_valid(parent_node):
			parent_node.add_child(field)
		else:
			add_child(field)
		
		field.global_position = field_data.position
		
		# Spawn all asteroids in the field
		for asteroid_data in field_data.asteroids:
			var asteroid = spawn_asteroid_from_data(asteroid_data, field)
			if asteroid:
				# Set position relative to field
				asteroid.position = asteroid_data.position - field_data.position
		
		# Register entity with data
		register_entity_with_data(field, field_data)
		
		return field
	
	# Use asteroid field scene if available
	var field = asteroid_scenes[1].instantiate()
	
	# Add to parent or to scene
	if parent_node and is_instance_valid(parent_node):
		parent_node.add_child(field)
	else:
		add_child(field)
	
	field.global_position = field_data.position
	field.name = "AsteroidField_" + str(field_data.entity_id)
	
	# Configure field properties if available
	if field.has_method("set_field_properties"):
		field.set_field_properties(
			field_data.field_radius,
			field_data.min_asteroids,
			field_data.max_asteroids
		)
	
	# Generate field
	if field.has_method("generate_field_from_data"):
		field.generate_field_from_data(field_data)
	else:
		# Manually spawn asteroids
		for asteroid_data in field_data.asteroids:
			var asteroid = spawn_asteroid_from_data(asteroid_data, field)
			if asteroid:
				# Set position relative to field
				asteroid.position = asteroid_data.position - field_data.position
	
	# Register entity with data
	register_entity_with_data(field, field_data)
	
	return field

# Spawn station from data
func spawn_station_from_data(station_data, parent_node = null):
	if station_scenes.is_empty():
		push_error("EntityManager: No station scene available")
		return null
	
	# Use appropriate station scene based on type if available
	var station_scene = station_scenes[0]  # Default to first
	
	if station_scenes.size() > station_data.station_type + 1:
		station_scene = station_scenes[station_data.station_type + 1]
	
	var station = station_scene.instantiate()
	
	# Add to parent or to scene
	if parent_node and is_instance_valid(parent_node):
		parent_node.add_child(station)
	else:
		add_child(station)
	
	# Set position
	station.global_position = station_data.position
	
	# Configure station
	if station.has_method("initialize"):
		station.initialize(station_data.seed_value)
	
	# Set basic properties
	if has_property(station, "station_type"):
		station.station_type = station_data.station_type
	
	if has_property(station, "station_name"):
		station.station_name = station_data.station_name
	
	if has_property(station, "level"):
		station.level = station_data.level
	
	# Set name if available
	if station_data.station_name:
		station.name = station_data.station_name
	
	# Register entity with data
	register_entity_with_data(station, station_data)
	
	return station

# --- Query Methods ---

# Get entity by ID
func get_entity_by_id(entity_id):
	for entity_type in entities:
		if entities[entity_type].has(entity_id):
			return entities[entity_type][entity_id]
	return null

# Get entity data for an entity
func get_entity_data(entity):
	if _entity_data_map.has(entity):
		return _entity_data_map[entity]
	return null

# Get player ship
func get_player_ship():
	if not entities.has("player") or entities.player.is_empty():
		return null
	
	# Return the first player found
	for entity_id in entities.player:
		return entities.player[entity_id]
	
	return null

# Get nearest entity of a specific type to a position
func get_nearest_entity(from_position, entity_type = ""):
	var nearest_entity = null
	var nearest_distance = INF
	
	# Determine which type dictionaries to search
	var type_dicts = {}
	if entity_type.is_empty():
		type_dicts = entities
	elif entities.has(entity_type):
		type_dicts[entity_type] = entities[entity_type]
	else:
		return null
	
	# Search for nearest entity
	for type in type_dicts:
		for entity_id in type_dicts[type]:
			var entity = type_dicts[type][entity_id]
			
			if not is_instance_valid(entity) or not "global_position" in entity:
				continue
			
			var distance = from_position.distance_to(entity.global_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_entity = entity
	
	return nearest_entity

# Get entities in radius
func get_entities_in_radius(from_position, radius, entity_type = "", exclude_entity = null):
	var entities_in_radius = []
	
	# Determine which type dictionaries to search
	var type_dicts = {}
	if entity_type.is_empty():
		type_dicts = entities
	elif entities.has(entity_type):
		type_dicts[entity_type] = entities[entity_type]
	else:
		return entities_in_radius
	
	# Search for entities in radius
	for type in type_dicts:
		for entity_id in type_dicts[type]:
			var entity = type_dicts[type][entity_id]
			
			if entity == exclude_entity or not is_instance_valid(entity) or not "global_position" in entity:
				continue
			
			var distance = from_position.distance_to(entity.global_position)
			if distance <= radius:
				entities_in_radius.append(entity)
	
	return entities_in_radius

# Despawn all entities of a specific type
func despawn_type(entity_type = ""):
	if not entities.has(entity_type):
		return
	
	# Create a copy of the keys to avoid modification during iteration
	var entity_ids = entities[entity_type].keys()
	
	for entity_id in entity_ids:
		var entity = entities[entity_type][entity_id]
		if is_instance_valid(entity):
			entity.queue_free()

# Despawn all entities
func despawn_all(exclude_player = false):
	# Create a copy of the entity types to avoid modification during iteration
	var entity_types = entities.keys()
	
	for entity_type in entity_types:
		if exclude_player and entity_type == "player":
			continue
			
		despawn_type(entity_type)

# Helper function to check if an object has a property
func has_property(obj: Object, property_name: String) -> bool:
	for property in obj.get_property_list():
		if property.name == property_name:
			return true
	return false
