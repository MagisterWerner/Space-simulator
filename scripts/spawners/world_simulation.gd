extends Node
class_name WorldSimulation

# Signals
signal world_loaded(world_data)
signal world_unloaded
signal entities_spawned(total_count)
signal entity_spawned(entity, entity_data)

# Configuration
@export_category("World Configuration")
@export var auto_load_world: bool = true
@export var center_camera_on_player: bool = true
@export var default_world_path: String = ""

@export_category("Spawning Configuration")
@export var spawn_batch_size: int = 10
@export var spawn_delay_between_batches: float = 0.05

@export_category("Debug")
@export var debug_mode: bool = false

# World data
var current_world_data: WorldData = null
var loaded_world_id: String = ""

# Spawner tracking
var _spawners: Dictionary = {}  # Type to spawner mapping
var _entities_to_spawn: Array = []
var _is_spawning: bool = false
var _spawn_timer: float = 0.0
var _spawn_count: int = 0

# References
var _game_settings = null
var _seed_manager = null
var _entity_manager = null
var _camera = null

func _ready() -> void:
	# Find references
	_game_settings = get_tree().current_scene.get_node_or_null("GameSettings")
	_seed_manager = get_node_or_null("/root/SeedManager")
	_entity_manager = get_node_or_null("/root/EntityManager")
	
	if _game_settings:
		debug_mode = _game_settings.debug_mode and _game_settings.debug_world_generator
	
	# Register specialized spawners
	_register_default_spawners()
	
	# Auto-load world if enabled
	if auto_load_world and not default_world_path.is_empty():
		call_deferred("load_world_from_file", default_world_path)

func _process(delta: float) -> void:
	if _is_spawning:
		_spawn_timer += delta
		
		if _spawn_timer >= spawn_delay_between_batches:
			_spawn_timer = 0.0
			_spawn_entity_batch()

# Register the standard set of entity spawners
func _register_default_spawners() -> void:
	# Create specialized spawners
	var planet_spawner = PlanetSpawner.new()
	planet_spawner.name = "PlanetSpawner"
	add_child(planet_spawner)
	_register_spawner("planet", planet_spawner)
	
	var asteroid_spawner = AsteroidSpawnerNew.new()
	asteroid_spawner.name = "AsteroidSpawner"
	add_child(asteroid_spawner)
	_register_spawner("asteroid", asteroid_spawner)
	_register_spawner("asteroid_field", asteroid_spawner)
	
	var station_spawner = StationSpawner.new()
	station_spawner.name = "StationSpawner"
	add_child(station_spawner)
	_register_spawner("station", station_spawner)
	
	if debug_mode:
		print("WorldSimulation: Registered default spawners")

# Register a spawner for a specific entity type
func _register_spawner(entity_type: String, spawner: EntitySpawner) -> void:
	_spawners[entity_type] = spawner
	
	# Connect spawner signals
	if not spawner.is_connected("entity_spawned", _on_entity_spawned):
		spawner.connect("entity_spawned", _on_entity_spawned)

# Generate a world with specified parameters
func generate_new_world(seed_value: int = 0) -> void:
	# Clear current world first
	unload_world()
	
	# Use provided seed or generate a new one
	if seed_value == 0 and _seed_manager:
		seed_value = _seed_manager.get_seed()
	
	if debug_mode:
		print("WorldSimulation: Generating new world with seed ", seed_value)
	
	# Use the adapter to generate world data
	var world_generator_adapter = WorldGeneratorAdapter.new()
	add_child(world_generator_adapter)
	
	# Connect to world generation completion
	world_generator_adapter.connect("world_data_generated", _on_world_data_generated)
	
	# Configure with game settings
	if _game_settings:
		world_generator_adapter._find_game_settings()
	
	# Generate the world
	world_generator_adapter.generate_world_data()
	
	# Note: The world_data_generated signal will be emitted when generation is complete

# Load a world from data
func load_world(world_data: WorldData) -> void:
	if world_data == null:
		push_error("WorldSimulation: Cannot load null world data")
		return
	
	# Unload current world if any
	unload_world()
	
	# Store the world data
	current_world_data = world_data
	loaded_world_id = world_data.world_id
	
	if debug_mode:
		print("WorldSimulation: Loading world with ID: ", loaded_world_id)
		print("WorldSimulation: World contains ", world_data.entities.size(), " entities")
	
	# Set the seed if needed
	if _seed_manager:
		_seed_manager.set_seed(world_data.seed_value)
	
	# Setup player starting position
	if world_data.player_start_position != Vector2.ZERO:
		if has_node("/root/GameManager") and GameManager.has_method("set_player_start_position"):
			GameManager.set_player_start_position(world_data.player_start_position, world_data.player_start_cell)
	
	# Queue entities for spawning
	_queue_entities_for_spawning(world_data.entities)
	
	# Begin spawning process
	_is_spawning = true
	_spawn_timer = 0.0
	
	# Emit world loaded signal
	world_loaded.emit(world_data)

# Load a world from a file
func load_world_from_file(file_path: String) -> void:
	if not FileAccess.file_exists(file_path):
		push_error("WorldSimulation: World file does not exist: " + file_path)
		return
	
	var world_data = WorldData.load_from_file(file_path)
	if world_data:
		load_world(world_data)
	else:
		push_error("WorldSimulation: Failed to load world data from file: " + file_path)

# Unload the current world
func unload_world() -> void:
	if current_world_data == null:
		return
	
	if debug_mode:
		print("WorldSimulation: Unloading world with ID: ", loaded_world_id)
	
	# Stop any ongoing spawning
	_is_spawning = false
	_entities_to_spawn.clear()
	
	# Despawn all entities
	for entity_type in _spawners:
		var spawner = _spawners[entity_type]
		spawner.despawn_all()
	
	# Clear references
	current_world_data = null
	loaded_world_id = ""
	
	# Emit signal
	world_unloaded.emit()

# Queue entities for spawning in batches
func _queue_entities_for_spawning(entities: Array) -> void:
	_entities_to_spawn = entities.duplicate()
	_spawn_count = 0
	
	if debug_mode:
		print("WorldSimulation: Queued ", _entities_to_spawn.size(), " entities for spawning")

# Spawn a batch of entities
func _spawn_entity_batch() -> void:
	var batch_size = min(spawn_batch_size, _entities_to_spawn.size())
	
	if batch_size == 0:
		_is_spawning = false
		
		if debug_mode:
			print("WorldSimulation: Finished spawning all entities, total: ", _spawn_count)
			
		entities_spawned.emit(_spawn_count)
		return
	
	for i in range(batch_size):
		if _entities_to_spawn.is_empty():
			break
			
		var entity_data = _entities_to_spawn.pop_front()
		_spawn_entity(entity_data)
		_spawn_count += 1

# Spawn a single entity
func _spawn_entity(entity_data) -> void:
	var entity_type = entity_data.entity_type
	
	# Get the appropriate spawner
	var spawner = _spawners.get(entity_type)
	if not spawner:
		if debug_mode:
			print("WorldSimulation: No spawner registered for entity type: ", entity_type)
		return
	
	# Spawn the entity
	spawner.spawn_entity(entity_data)

# Event handlers
func _on_world_data_generated(world_data: WorldData) -> void:
	if debug_mode:
		print("WorldSimulation: Received generated world data")
	
	# Remove the adapter
	var adapter = get_node_or_null("WorldGeneratorAdapter")
	if adapter:
		adapter.queue_free()
	
	# Load the generated world
	load_world(world_data)

func _on_entity_spawned(entity: Node, entity_data) -> void:
	# Re-emit the signal
	entity_spawned.emit(entity, entity_data)
	
	# Center camera on player if needed
	if center_camera_on_player and entity.is_in_group("player"):
		_find_and_center_camera(entity)

func _find_and_center_camera(player_entity: Node) -> void:
	if not _camera:
		_camera = get_viewport().get_camera_2d()
		
	if not _camera:
		var main = get_tree().current_scene
		_camera = main.get_node_or_null("Camera2D")
	
	if _camera and player_entity is Node2D:
		_camera.global_position = player_entity.global_position

# Get an entity by ID
func get_entity_by_id(entity_id: int) -> Node:
	# Try each spawner
	for entity_type in _spawners:
		var spawner = _spawners[entity_type]
		var entity = spawner.get_entity(entity_id)
		if entity:
			return entity
	
	return null

# Get all entities of a specified type
func get_entities_by_type(entity_type: String) -> Array:
	var spawner = _spawners.get(entity_type)
	if spawner:
		return spawner.get_all_entities()
	return []

# Save current world to file
func save_world_to_file(file_path: String) -> bool:
	if current_world_data == null:
		push_error("WorldSimulation: No world data to save")
		return false
	
	return current_world_data.save_to_file(file_path)

# Cleanup and free all resources
func cleanup() -> void:
	unload_world()
	
	# Clean up all spawners
	for entity_type in _spawners:
		_spawners[entity_type].cleanup()
