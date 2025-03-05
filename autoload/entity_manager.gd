# autoload/entity_manager.gd
#
# Entities Singleton
# =================
# Purpose:
#   Manages all game entities (players, ships, asteroids, stations).
#   Provides centralized entity registration, spawning, and lookup.
#
# Interface:
#   - Entity Registration: register_entity(), deregister_entity()
#   - Entity Spawning: spawn_player(), spawn_enemy_ship(), spawn_asteroid(), spawn_station()
#   - Entity Queries: get_nearest_entity(), get_entities_in_radius(), despawn_all()
#   - Signals: entity_spawned, entity_despawned, player_spawned
#
# Usage:
#   Access via the Entities autoload:
#   ```
#   # Spawn the player
#   var player = Entities.spawn_player(spawn_position)
#   
#   # Find the nearest asteroid to the player
#   var nearest_asteroid = Entities.get_nearest_entity(player.global_position, "asteroid")
#   ```
#
extends Node
class_name EntityManager

signal entity_spawned(entity, entity_type)
signal entity_despawned(entity, entity_type)
signal player_spawned(player)

# Entity dictionaries for different types
var players: Dictionary = {}  # player_id -> player_node
var ships: Dictionary = {}    # ship_id -> ship_node
var asteroids: Dictionary = {}  # asteroid_id -> asteroid_node
var stations: Dictionary = {}  # station_id -> station_node

# Entity counter for generating unique IDs
var entity_counter: int = 0

# Entity scenes - now using preloaded scenes instead of exported variables
var player_ship_scene: PackedScene = null
var enemy_ship_scenes: Array[PackedScene] = []
var asteroid_scenes: Array[PackedScene] = []
var station_scenes: Array[PackedScene] = []

# Initialization flag
var _scenes_initialized: bool = false

func _ready() -> void:
	# Set up process mode to continue during pause
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Initialize scenes
	_initialize_scenes()

func _initialize_scenes() -> void:
	if _scenes_initialized:
		return
	
	# Load player ship scene
	player_ship_scene = load("res://scenes/player/player_ship.tscn")
	
	# Load asteroid scenes (add your actual paths)
	# Example: asteroid_scenes.append(load("res://asteroids/asteroid_small.tscn"))
	
	# Load enemy ship scenes (add your actual paths)
	# Example: enemy_ship_scenes.append(load("res://enemies/enemy_basic.tscn"))
	
	# Load station scenes (add your actual paths)
	# Example: station_scenes.append(load("res://stations/trading_station.tscn"))
	
	_scenes_initialized = true

func register_entity(entity: Node, entity_type: String = "generic") -> int:
	# Generate a unique ID for the entity
	entity_counter += 1
	var entity_id = entity_counter
	
	# Store the entity in the appropriate dictionary
	match entity_type:
		"player":
			players[entity_id] = entity
			player_spawned.emit(entity)
		"ship":
			ships[entity_id] = entity
		"asteroid":
			asteroids[entity_id] = entity
		"station":
			stations[entity_id] = entity
	
	# Set up entity ID metadata
	entity.set_meta("entity_id", entity_id)
	entity.set_meta("entity_type", entity_type)
	
	# Connect to tree_exiting signal to automatically deregister
	if not entity.tree_exiting.is_connected(_on_entity_tree_exiting):
		entity.tree_exiting.connect(_on_entity_tree_exiting.bind(entity))
	
	entity_spawned.emit(entity, entity_type)
	return entity_id

func deregister_entity(entity: Node) -> void:
	if not entity.has_meta("entity_id") or not entity.has_meta("entity_type"):
		return
	
	var entity_id = entity.get_meta("entity_id")
	var entity_type = entity.get_meta("entity_type")
	
	# Remove from the appropriate dictionary
	match entity_type:
		"player":
			players.erase(entity_id)
		"ship":
			ships.erase(entity_id)
		"asteroid":
			asteroids.erase(entity_id)
		"station":
			stations.erase(entity_id)
	
	entity_despawned.emit(entity, entity_type)

func _on_entity_tree_exiting(entity: Node) -> void:
	deregister_entity(entity)

func spawn_player(spawn_position: Vector2 = Vector2.ZERO) -> Node:
	# Ensure scenes are initialized
	_initialize_scenes()
	
	if not player_ship_scene:
		push_error("EntityManager: player_ship_scene not set")
		return null
	
	var player = player_ship_scene.instantiate()
	add_child(player)
	
	# Position the player
	player.global_position = spawn_position
	
	# Register the player
	register_entity(player, "player")
	
	return player

func spawn_enemy_ship(type_index: int = 0, spawn_position: Vector2 = Vector2.ZERO) -> Node:
	# Ensure scenes are initialized
	_initialize_scenes()
	
	if enemy_ship_scenes.is_empty():
		push_error("EntityManager: enemy_ship_scenes array is empty")
		return null
	
	if type_index < 0 or type_index >= enemy_ship_scenes.size():
		type_index = 0
	
	var ship = enemy_ship_scenes[type_index].instantiate()
	add_child(ship)
	
	# Position the ship
	ship.global_position = spawn_position
	
	# Register the ship
	register_entity(ship, "ship")
	
	return ship

func spawn_asteroid(type_index: int = -1, spawn_position: Vector2 = Vector2.ZERO) -> Node:
	# Ensure scenes are initialized
	_initialize_scenes()
	
	if asteroid_scenes.is_empty():
		# Create a default asteroid if none are defined
		var default_asteroid = Node2D.new()
		default_asteroid.name = "DefaultAsteroid"
		
		# Add to scene and register
		add_child(default_asteroid)
		default_asteroid.global_position = spawn_position
		register_entity(default_asteroid, "asteroid")
		return default_asteroid
	
	# Random type if not specified
	if type_index < 0 or type_index >= asteroid_scenes.size():
		type_index = randi() % asteroid_scenes.size()
	
	var asteroid = asteroid_scenes[type_index].instantiate()
	add_child(asteroid)
	
	# Position the asteroid
	asteroid.global_position = spawn_position
	
	# Register the asteroid
	register_entity(asteroid, "asteroid")
	
	return asteroid

func spawn_station(type_index: int = 0, spawn_position: Vector2 = Vector2.ZERO) -> Node:
	# Ensure scenes are initialized
	_initialize_scenes()
	
	if station_scenes.is_empty():
		# Create a default station if none are defined
		var default_station = Node2D.new()
		default_station.name = "DefaultStation"
		
		# Add to scene and register
		add_child(default_station)
		default_station.global_position = spawn_position
		register_entity(default_station, "station")
		return default_station
	
	if type_index < 0 or type_index >= station_scenes.size():
		type_index = 0
	
	var station = station_scenes[type_index].instantiate()
	add_child(station)
	
	# Position the station
	station.global_position = spawn_position
	
	# Register the station
	register_entity(station, "station")
	
	return station

func get_nearest_entity(from_position: Vector2, entity_type: String = "", exclude_entity: Node = null) -> Node:
	var entity_dict: Dictionary
	
	# Select the appropriate dictionary based on entity type
	match entity_type:
		"player":
			entity_dict = players
		"ship":
			entity_dict = ships
		"asteroid":
			entity_dict = asteroids
		"station":
			entity_dict = stations
		_:
			# Combine all dictionaries if no specific type
			entity_dict = {}
			entity_dict.merge(players)
			entity_dict.merge(ships)
			entity_dict.merge(asteroids)
			entity_dict.merge(stations)
	
	var nearest_entity: Node = null
	var nearest_distance: float = INF
	
	# Find the nearest entity
	for entity_id in entity_dict:
		var entity = entity_dict[entity_id]
		
		if entity == exclude_entity or not is_instance_valid(entity):
			continue
		
		var distance = from_position.distance_to(entity.global_position)
		
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_entity = entity
	
	return nearest_entity

func get_entities_in_radius(from_position: Vector2, radius: float, entity_type: String = "", exclude_entity: Node = null) -> Array:
	var entity_dict: Dictionary
	
	# Select the appropriate dictionary based on entity type
	match entity_type:
		"player":
			entity_dict = players
		"ship":
			entity_dict = ships
		"asteroid":
			entity_dict = asteroids
		"station":
			entity_dict = stations
		_:
			# Combine all dictionaries if no specific type
			entity_dict = {}
			entity_dict.merge(players)
			entity_dict.merge(ships)
			entity_dict.merge(asteroids)
			entity_dict.merge(stations)
	
	var entities_in_radius: Array = []
	
	# Find all entities in the radius
	for entity_id in entity_dict:
		var entity = entity_dict[entity_id]
		
		if entity == exclude_entity or not is_instance_valid(entity):
			continue
		
		var distance = from_position.distance_to(entity.global_position)
		
		if distance <= radius:
			entities_in_radius.append(entity)
	
	return entities_in_radius

func despawn_all(entity_type: String = "") -> void:
	# Despawn all entities of the specified type, or all entities if no type is specified
	var entities_to_despawn: Array = []
	
	match entity_type:
		"player":
			entities_to_despawn = players.values()
		"ship":
			entities_to_despawn = ships.values()
		"asteroid":
			entities_to_despawn = asteroids.values()
		"station":
			entities_to_despawn = stations.values()
		_:
			# Despawn all entities
			entities_to_despawn.append_array(players.values())
			entities_to_despawn.append_array(ships.values())
			entities_to_despawn.append_array(asteroids.values())
			entities_to_despawn.append_array(stations.values())
	
	# Despawn each entity
	for entity in entities_to_despawn:
		if is_instance_valid(entity):
			entity.queue_free()
