extends Node

signal entity_spawned(entity, entity_type)
signal entity_despawned(entity, entity_type)
signal player_spawned(player)

# Consolidated entity storage
var entities = {
	"player": {},
	"ship": {},
	"asteroid": {},
	"station": {}
}

# Entity counter for generating unique IDs
var entity_counter = 0

# Entity scenes
var player_ship_scene = null
var enemy_ship_scenes = []
var asteroid_scenes = []
var station_scenes = []

# Initialization flag
var _scenes_initialized = false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_initialize_scenes")

func _initialize_scenes():
	if _scenes_initialized: return
	
	# Load player ship scene
	player_ship_scene = load("res://scenes/player/player_ship.tscn")
	
	# These would be populated with actual paths in a real implementation
	# asteroid_scenes.append(load("res://asteroids/asteroid_small.tscn"))
	# enemy_ship_scenes.append(load("res://enemies/enemy_basic.tscn"))
	# station_scenes.append(load("res://stations/trading_station.tscn"))
	
	_scenes_initialized = true

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

func deregister_entity(entity):
	if not entity.has_meta("entity_id") or not entity.has_meta("entity_type"):
		return
	
	var entity_id = entity.get_meta("entity_id")
	var entity_type = entity.get_meta("entity_type")
	
	# Remove from the dictionary if it exists
	if entities.has(entity_type) and entities[entity_type].has(entity_id):
		entities[entity_type].erase(entity_id)
	
	entity_despawned.emit(entity, entity_type)

func _on_entity_tree_exiting(entity):
	deregister_entity(entity)

# --- Spawning Methods ---

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

func spawn_enemy_ship(type_index = 0, spawn_position = Vector2.ZERO):
	_initialize_scenes()
	
	if enemy_ship_scenes.is_empty():
		push_error("EntityManager: enemy_ship_scenes array is empty")
		return null
	
	if type_index < 0 or type_index >= enemy_ship_scenes.size():
		type_index = 0
	
	var ship = enemy_ship_scenes[type_index].instantiate()
	add_child(ship)
	ship.global_position = spawn_position
	register_entity(ship, "ship")
	
	return ship

func spawn_asteroid(type_index = -1, spawn_position = Vector2.ZERO):
	_initialize_scenes()
	
	if asteroid_scenes.is_empty():
		# Create a default asteroid if none are defined
		var default_asteroid = Node2D.new()
		default_asteroid.name = "DefaultAsteroid"
		add_child(default_asteroid)
		default_asteroid.global_position = spawn_position
		register_entity(default_asteroid, "asteroid")
		return default_asteroid
	
	# Random type if not specified
	if type_index < 0 or type_index >= asteroid_scenes.size():
		type_index = randi() % asteroid_scenes.size()
	
	var asteroid = asteroid_scenes[type_index].instantiate()
	add_child(asteroid)
	asteroid.global_position = spawn_position
	register_entity(asteroid, "asteroid")
	
	return asteroid

func spawn_station(type_index = 0, spawn_position = Vector2.ZERO):
	_initialize_scenes()
	
	if station_scenes.is_empty():
		# Create a default station if none are defined
		var default_station = Node2D.new()
		default_station.name = "DefaultStation"
		add_child(default_station)
		default_station.global_position = spawn_position
		register_entity(default_station, "station")
		return default_station
	
	if type_index < 0 or type_index >= station_scenes.size():
		type_index = 0
	
	var station = station_scenes[type_index].instantiate()
	add_child(station)
	station.global_position = spawn_position
	register_entity(station, "station")
	
	return station

# --- Query Methods ---

func get_nearest_entity(from_position, entity_type = "", exclude_entity = null):
	var nearest_entity = null
	var nearest_distance = INF
	
	# Get the appropriate entity dictionaries
	var entity_dicts = {}
	if entity_type.is_empty():
		entity_dicts = entities
	elif entities.has(entity_type):
		entity_dicts[entity_type] = entities[entity_type]
	else:
		return null
	
	# Find the nearest entity
	for type in entity_dicts:
		for entity_id in entity_dicts[type]:
			var entity = entity_dicts[type][entity_id]
			
			if entity == exclude_entity or not is_instance_valid(entity):
				continue
			
			var distance = from_position.distance_to(entity.global_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_entity = entity
	
	return nearest_entity

func get_entities_in_radius(from_position, radius, entity_type = "", exclude_entity = null):
	var entities_in_radius = []
	
	# Get the appropriate entity dictionaries
	var entity_dicts = {}
	if entity_type.is_empty():
		entity_dicts = entities
	elif entities.has(entity_type):
		entity_dicts[entity_type] = entities[entity_type]
	else:
		return entities_in_radius
	
	# Find all entities in the radius
	for type in entity_dicts:
		for entity_id in entity_dicts[type]:
			var entity = entity_dicts[type][entity_id]
			
			if entity == exclude_entity or not is_instance_valid(entity):
				continue
			
			var distance = from_position.distance_to(entity.global_position)
			if distance <= radius:
				entities_in_radius.append(entity)
	
	return entities_in_radius

func despawn_all(entity_type = ""):
	var to_despawn = []
	
	if entity_type.is_empty():
		# Collect all entities
		for type in entities:
			to_despawn.append_array(entities[type].values())
	elif entities.has(entity_type):
		to_despawn = entities[entity_type].values()
	
	# Despawn each entity
	for entity in to_despawn:
		if is_instance_valid(entity):
			entity.queue_free()
