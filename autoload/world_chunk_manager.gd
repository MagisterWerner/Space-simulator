# autoload/world_chunk_manager.gd
# World Chunk Manager refactored with dependency injection

extends "res://autoload/base_service.gd"

signal chunk_loaded(chunk_coords: Vector2i)
signal chunk_unloaded(chunk_coords: Vector2i)

#------------------------------------------------------------------
# Configuration Properties
#------------------------------------------------------------------

# Chunk configuration
@export var chunk_size: int = 1000  # Size of each chunk in world units
@export var view_distance: int = 2  # How many chunks to load in each direction
@export var preload_distance: int = 3  # Chunks to preload but with lower detail

# Performance configuration
@export var thread_count: int = 2  # Number of worker threads for async loading
@export var entities_per_frame: int = 5  # Max entities to generate per frame
@export var max_entities_per_chunk: int = 50  # Limit entities per chunk
@export var generation_budget_ms: float = 5.0  # Max milliseconds per frame for generation

# Scene references 
@export var chunk_scene: PackedScene
@export var entity_scenes: Dictionary = {
	"asteroid": null,
	"enemy_ship": null,
	"station": null
}

# Service references
var seed_manager = null
var entity_manager = null

#------------------------------------------------------------------
# Internal State
#------------------------------------------------------------------

# Chunk tracking
var _loaded_chunks: Dictionary = {}  # Chunks that are fully loaded
var _preloaded_chunks: Dictionary = {}  # Chunks that are preloaded with minimal content
var _loading_queue: Array = []  # Queue of chunks to load
var _unloading_queue: Array = []  # Queue of chunks to unload
var _player_chunk: Vector2i = Vector2i.ZERO  # Current chunk the player is in

# Threading
var _generation_thread_pool: Array = []
var _thread_mutex: Mutex
var _thread_semaphore: Semaphore
var _exit_thread: bool = false

# Object pools
var _entity_pools: Dictionary = {}

func _ready() -> void:
	# Register self with ServiceLocator
	call_deferred("register_self")
	
	# Skip in editor
	if Engine.is_editor_hint():
		return
		
	# Initialize object pools
	for entity_type in entity_scenes:
		_entity_pools[entity_type] = []
	
	# Initialize threading components
	_thread_mutex = Mutex.new()
	_thread_semaphore = Semaphore.new()
	
	# Try to load entity scenes if they exist
	_try_load_entity_scenes()

# Return dependencies required by this service
func get_dependencies() -> Array:
	return ["SeedManager"] # Required dependency

# Initialize this service
func initialize_service() -> void:
	# Get SeedManager dependency
	seed_manager = get_dependency("SeedManager")
	
	# Connect to SeedManager signals
	connect_to_dependency("SeedManager", "seed_changed", _on_seed_changed)
	
	# Get optional EntityManager dependency
	if has_dependency("EntityManager"):
		entity_manager = get_dependency("EntityManager")
	
	# Start worker threads
	for i in range(thread_count):
		var thread = Thread.new()
		thread.start(_thread_worker)
		_generation_thread_pool.append(thread)
	
	# Mark as initialized
	_service_initialized = true
	print("WorldChunkManager: Service initialized successfully")

# Try to load entity scenes if they exist in the project
func _try_load_entity_scenes():
	var paths = {
		"asteroid": "res://scenes/entities/asteroid.tscn",
		"enemy_ship": "res://scenes/entities/enemy_ship.tscn",
		"station": "res://scenes/entities/station.tscn"
	}
	
	for type in paths:
		var path = paths[type]
		if ResourceLoader.exists(path):
			entity_scenes[type] = load(path)
		else:
			print("Scene file not found: %s - will need to be set manually" % path)

#------------------------------------------------------------------
# Public Configuration Methods
#------------------------------------------------------------------

# Public method to configure and initialize the manager
func configure(config: Dictionary = {}):
	if config.has("chunk_scene") and config.chunk_scene != null:
		chunk_scene = config.chunk_scene
	
	if config.has("entity_scenes") and config.entity_scenes != null:
		# Update entity scenes
		for type in config.entity_scenes:
			if config.entity_scenes[type] != null:
				entity_scenes[type] = config.entity_scenes[type]
				# Ensure we have a pool for this type
				if not _entity_pools.has(type):
					_entity_pools[type] = []
	
	if config.has("view_distance"):
		view_distance = config.view_distance
	
	if config.has("preload_distance"):
		preload_distance = config.preload_distance
		
	if config.has("chunk_size"):
		chunk_size = config.chunk_size
	
	print("WorldChunkManager configured with:")
	print("- Chunk scene: ", chunk_scene)
	print("- Entity scenes: ", entity_scenes.keys())
	
	# Return self for method chaining
	return self

# Check if the system is properly configured
func is_ready_to_use() -> bool:
	# Check if we have a chunk scene
	if not chunk_scene:
		return false
		
	# Check if we have at least one valid entity type
	var has_valid_entity = false
	for type in entity_scenes:
		if entity_scenes[type] != null:
			has_valid_entity = true
			break
			
	return has_valid_entity

# Helper method to create a minimal placeholder chunk scene
func create_debug_chunk_scene() -> PackedScene:
	# Create a simple chunk scene for debugging
	var node = Node2D.new()
	var script = load("res://scripts/world/world_chunk.gd")
	if script:
		node.set_script(script)
	
	# Create a scene from this node
	var packed_scene = PackedScene.new()
	packed_scene.pack(node)
	
	return packed_scene

#------------------------------------------------------------------
# Coordinate Conversion Methods
#------------------------------------------------------------------

# Convert world position to chunk coordinates
func world_to_chunk(world_pos: Vector2) -> Vector2i:
	var x = int(floor(world_pos.x / chunk_size))
	var y = int(floor(world_pos.y / chunk_size))
	return Vector2i(x, y)

# Convert chunk coordinates to world position (chunk center)
func chunk_to_world(chunk_coords: Vector2i) -> Vector2:
	var x = (chunk_coords.x * chunk_size) + (chunk_size / 2)
	var y = (chunk_coords.y * chunk_size) + (chunk_size / 2)
	return Vector2(x, y)

#------------------------------------------------------------------
# Main Processing
#------------------------------------------------------------------

func _process(delta):
	# Skip processing if not properly configured
	if not is_ready_to_use():
		return
		
	# Process chunk loading/unloading queue
	_process_chunk_queues(delta)
	
	# Update player position and manage chunks
	var player = null
	
	# Try to get player through EntityManager first
	if entity_manager:
		player = entity_manager.get_nearest_entity(Vector2.ZERO, "player")
	else:
		# Fallback to direct scene tree query
		var player_ships = get_tree().get_nodes_in_group("player")
		if not player_ships.is_empty():
			player = player_ships[0]
	
	if player:
		var new_player_chunk = world_to_chunk(player.global_position)
		if new_player_chunk != _player_chunk:
			_player_chunk = new_player_chunk
			_update_chunk_priorities()

# Process chunk loading/unloading queues with time budget
func _process_chunk_queues(delta):
	var start_time = Time.get_ticks_msec()
	var time_budget = generation_budget_ms
	
	# Process unloading queue first (frees resources)
	while _unloading_queue.size() > 0 and (Time.get_ticks_msec() - start_time) < time_budget:
		var coords = _unloading_queue.pop_front()
		unload_chunk(coords)
	
	# Process loading queue with remaining time budget
	var entities_processed = 0
	while _loading_queue.size() > 0 and entities_processed < entities_per_frame and (Time.get_ticks_msec() - start_time) < time_budget:
		var item = _loading_queue[0]
		
		# If worker threads available, use them for distant chunks
		var distance_to_player = (_player_chunk - item.coords).length()
		if distance_to_player > 1 and thread_count > 0:
			# Signal worker thread to handle this chunk
			_thread_mutex.lock()
			var task = _loading_queue.pop_front()
			_thread_mutex.unlock()
			_thread_semaphore.post()
		else:
			# Load chunk on main thread for nearby chunks
			var coords = _loading_queue.pop_front().coords
			load_chunk(coords)
			entities_processed += 1

#------------------------------------------------------------------
# Chunk Priority Management
#------------------------------------------------------------------

# Update which chunks should be loaded/unloaded based on player position
func _update_chunk_priorities():
	var chunks_to_load = []
	var chunks_to_preload = []
	
	# Determine which chunks should be loaded (full detail)
	for x in range(_player_chunk.x - view_distance, _player_chunk.x + view_distance + 1):
		for y in range(_player_chunk.y - view_distance, _player_chunk.y + view_distance + 1):
			var coords = Vector2i(x, y)
			chunks_to_load.append(coords)
	
	# Determine which chunks should be preloaded (minimal detail)
	for x in range(_player_chunk.x - preload_distance, _player_chunk.x + preload_distance + 1):
		for y in range(_player_chunk.y - preload_distance, _player_chunk.y + preload_distance + 1):
			var coords = Vector2i(x, y)
			if not coords in chunks_to_load:
				chunks_to_preload.append(coords)
	
	# Queue chunks for loading if not already loaded
	for coords in chunks_to_load:
		if not coords in _loaded_chunks and not coords in _loading_queue:
			_loading_queue.append({"coords": coords, "priority": 0, "full_detail": true})
	
	# Queue chunks for preloading if not already loaded or preloaded
	for coords in chunks_to_preload:
		if not coords in _loaded_chunks and not coords in _preloaded_chunks and not coords in _loading_queue:
			_loading_queue.append({"coords": coords, "priority": 1, "full_detail": false})
	
	# Queue chunks for unloading if they're too far away
	for coords in _loaded_chunks.keys():
		if not coords in chunks_to_load and not coords in chunks_to_preload:
			_unloading_queue.append(coords)
	
	for coords in _preloaded_chunks.keys():
		if not coords in chunks_to_preload:
			_unloading_queue.append(coords)
	
	# Sort loading queue by priority
	_sort_loading_queue()

# Sort the loading queue by priority
func _sort_loading_queue():
	_loading_queue.sort_custom(func(a, b): 
		# Lower priority number = higher actual priority
		if a.priority != b.priority:
			return a.priority < b.priority
			
		# If same priority, sort by distance to player
		var a_distance = (_player_chunk - a.coords).length()
		var b_distance = (_player_chunk - b.coords).length()
		return a_distance < b_distance
	)

#------------------------------------------------------------------
# Chunk Loading and Unloading
#------------------------------------------------------------------

# Load a chunk at given coordinates
func load_chunk(coords: Vector2i):
	# Check if already loaded
	if coords in _loaded_chunks:
		return
		
	# Check if chunk_scene is set
	if not chunk_scene:
		push_error("Cannot load chunk: chunk_scene is not set")
		return
	
	# Generate chunk data
	var chunk_data = _generate_chunk_data(coords, true)
	
	# Create chunk node
	var chunk = chunk_scene.instantiate()
	chunk.initialize(coords, chunk_data, true)
	add_child(chunk)
	
	# Spawn entities from pool
	for entity_data in chunk_data.entities:
		var entity = _get_entity_from_pool(entity_data.type)
		if entity:
			entity.global_position = entity_data.position
			entity.rotation = entity_data.rotation
			# Only set entity_id if the property exists
			if entity.get("entity_id") != null:
				entity.entity_id = entity_data.id
			else:
				entity.set_meta("entity_id", entity_data.id)
			chunk.add_entity(entity)
	
	_loaded_chunks[coords] = chunk
	emit_signal("chunk_loaded", coords)

# Unload a chunk at given coordinates
func unload_chunk(coords: Vector2i):
	if coords in _loaded_chunks:
		var chunk = _loaded_chunks[coords]
		
		# Return entities to pool
		for entity in chunk.get_entities():
			_return_entity_to_pool(entity)
		
		# Remove chunk
		_loaded_chunks.erase(coords)
		chunk.queue_free()
		emit_signal("chunk_unloaded", coords)
		
	elif coords in _preloaded_chunks:
		var chunk = _preloaded_chunks[coords]
		_preloaded_chunks.erase(coords)
		chunk.queue_free()
		emit_signal("chunk_unloaded", coords)

#------------------------------------------------------------------
# Chunk Data Generation
#------------------------------------------------------------------

# Generate chunk data (deterministic based on seed)
func _generate_chunk_data(coords: Vector2i, full_detail: bool) -> Dictionary:
	# Create a consistent chunk ID
	var chunk_id = _get_chunk_id(coords)
	
	var data = {
		"entities": [],
		"background": {
			"type": 0,
			"density": 0.5
		}
	}
	
	# Use SeedManager for deterministic generation
	if seed_manager:
		data.background.type = seed_manager.get_random_int(chunk_id, 0, 3)
		data.background.density = seed_manager.get_random_value(chunk_id + 1, 0.1, 1.0)
	else:
		# Fallback if SeedManager not available
		var rng = RandomNumberGenerator.new()
		rng.seed = chunk_id
		data.background.type = rng.randi_range(0, 3)
		data.background.density = rng.randf_range(0.1, 1.0)
	
	# For preloaded chunks, only generate the minimum needed data
	if not full_detail:
		return data
	
	# Determine what entities should be in this chunk
	var entity_count = 15  # Default
	if seed_manager:
		entity_count = min(max_entities_per_chunk, seed_manager.get_random_int(chunk_id + 2, 5, 25))
	
	# Generate entities
	for i in range(entity_count):
		var entity_id = chunk_id + (i * 100)
		
		# Determine entity type
		var entity_type_roll = 0.0
		if seed_manager:
			entity_type_roll = seed_manager.get_random_value(entity_id, 0, 1)
		else:
			var rng = RandomNumberGenerator.new()
			rng.seed = entity_id
			entity_type_roll = rng.randf()
			
		var entity_type = "asteroid"
		if entity_type_roll > 0.8:
			entity_type = "enemy_ship"
		elif entity_type_roll > 0.95:
			entity_type = "station"
		
		# Skip if we don't have this entity type configured
		if not entity_scenes.has(entity_type) or entity_scenes[entity_type] == null:
			continue
		
		# Determine entity position within chunk
		var pos_x = 0.0
		var pos_y = 0.0
		
		if seed_manager:
			pos_x = seed_manager.get_random_value(entity_id + 1, 0, chunk_size)
			pos_y = seed_manager.get_random_value(entity_id + 2, 0, chunk_size)
		else:
			var rng = RandomNumberGenerator.new()
			rng.seed = entity_id
			pos_x = rng.randf() * chunk_size
			pos_y = rng.randf() * chunk_size
			
		var world_x = (coords.x * chunk_size) + pos_x
		var world_y = (coords.y * chunk_size) + pos_y
		
		var rotation = 0.0
		if seed_manager:
			rotation = seed_manager.get_random_value(entity_id + 3, 0, TAU)
		else:
			var rng = RandomNumberGenerator.new()
			rng.seed = entity_id + 3
			rotation = rng.randf() * TAU
		
		data.entities.append({
			"type": entity_type,
			"id": entity_id,
			"position": Vector2(world_x, world_y),
			"rotation": rotation
		})
	
	return data

# Get a consistent chunk ID for deterministic generation
func _get_chunk_id(coords: Vector2i) -> int:
	# Create a base chunk ID using the coordinate
	# We use prime multipliers to avoid grid patterns
	return 12347 + (coords.x * 7919) + (coords.y * 6837)

#------------------------------------------------------------------
# Threading
#------------------------------------------------------------------

# Thread worker function
func _thread_worker():
	while true:
		_thread_semaphore.wait()
		
		# Check if we're exiting
		if _exit_thread:
			break
			
		# Get a task from the queue
		_thread_mutex.lock()
		var task = null
		if _loading_queue.size() > 0:
			task = _loading_queue.pop_front()
		_thread_mutex.unlock()
		
		if task:
			# Prepare chunk data but don't instantiate scenes
			var chunk_data = _generate_chunk_data(task.coords, task.full_detail)
			
			# Send back to main thread for actual scene creation
			call_deferred("_finish_chunk_generation", task.coords, chunk_data, task.full_detail)

# Called from thread to finish chunk generation on main thread
func _finish_chunk_generation(coords: Vector2i, chunk_data: Dictionary, full_detail: bool):
	# Make sure chunk scene is available
	if not chunk_scene:
		push_error("Cannot create chunk: chunk_scene is not set")
		return
		
	var chunk = chunk_scene.instantiate()
	chunk.initialize(coords, chunk_data, full_detail)
	add_child(chunk)
	
	if full_detail:
		_loaded_chunks[coords] = chunk
	else:
		_preloaded_chunks[coords] = chunk
	
	emit_signal("chunk_loaded", coords)

#------------------------------------------------------------------
# Object Pooling
#------------------------------------------------------------------

# Get a reusable entity from the object pool
func _get_entity_from_pool(entity_type: String) -> Node:
	# Check if we have this entity type configured
	if not entity_scenes.has(entity_type) or entity_scenes[entity_type] == null:
		push_warning("Entity type %s not configured in WorldChunkManager" % entity_type)
		# Return a placeholder node instead of null
		var placeholder = Node2D.new()
		placeholder.name = "Placeholder_%s" % entity_type
		placeholder.set_meta("entity_type", entity_type)
		placeholder.set_meta("is_placeholder", true)
		return placeholder
		
	if _entity_pools[entity_type].size() > 0:
		return _entity_pools[entity_type].pop_back()
	else:
		var entity = entity_scenes[entity_type].instantiate()
		# Register with EntityManager if available
		if entity_manager and entity_manager.has_method("register_entity"):
			entity_manager.register_entity(entity, entity_type)
		return entity

# Return an entity to the object pool
func _return_entity_to_pool(entity: Node):
	var entity_type = entity.get_meta("entity_type", "asteroid")
	
	# Don't pool placeholder entities
	if entity.get_meta("is_placeholder", false):
		entity.queue_free()
		return
		
	# Check if entity still has a parent
	if entity.get_parent():
		entity.get_parent().remove_child(entity)
	
	# Reset entity state
	if entity.has_method("reset"):
		entity.reset()
	
	_entity_pools[entity_type].append(entity)

#------------------------------------------------------------------
# Event Handlers
#------------------------------------------------------------------

# Handle seed changes
func _on_seed_changed(new_seed):
	# Regenerate all loaded chunks
	var loaded_chunks_copy = _loaded_chunks.keys().duplicate()
	for chunk_coords in loaded_chunks_copy:
		unload_chunk(chunk_coords)
		load_chunk(chunk_coords)

#------------------------------------------------------------------
# Cleanup
#------------------------------------------------------------------

# Clean up threads
func _exit_tree():
	_exit_thread = true
	
	# Signal all threads to exit
	for i in range(_generation_thread_pool.size()):
		_thread_semaphore.post()
	
	# Wait for all threads to finish
	for thread in _generation_thread_pool:
		thread.wait_to_finish()
		
	# Clear all chunks
	for coords in _loaded_chunks.keys():
		unload_chunk(coords)
		
	for coords in _preloaded_chunks.keys():
		unload_chunk(coords)
