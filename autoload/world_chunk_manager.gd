# world_chunk_manager.gd
# An enhanced world chunk manager that handles asynchronous loading and unloading
# of world chunks as the player moves through the game world.
extends "res://autoload/base_service.gd"

signal chunk_loaded(chunk_coords: Vector2i, chunk: Node)
signal chunk_unloaded(chunk_coords: Vector2i)
signal low_detail_chunk_loaded(chunk_coords: Vector2i, chunk: Node)
signal player_entered_chunk(old_chunk: Vector2i, new_chunk: Vector2i)

# Configuration
@export_category("Chunk Configuration")
@export var chunk_size: int = 1024  # Size of each chunk in world units
@export var active_chunk_distance: int = 2  # Full detail chunks to load around player
@export var preload_chunk_distance: int = 4  # Distance for low detail preloading
@export var despawn_distance: int = 5  # Distance at which to completely unload chunks

@export_category("Performance")
@export var thread_count: int = 2  # Number of generation threads
@export var generation_budget_ms: float = 5.0  # Max ms per frame for generation
@export var entity_batch_size: int = 5  # Max entities to create per frame
@export var max_concurrent_loads: int = 3  # Max chunks loading at once
@export var min_wait_between_loads_ms: int = 150  # Increased to 150ms from 50ms

@export_category("References")
@export var chunk_scene: PackedScene  # Basic chunk scene

# Service references
var seed_manager = null
var entity_manager = null
var grid_manager = null
var event_manager = null
var world_generator = null
var game_settings = null

# Chunk tracking
var _loaded_chunks: Dictionary = {}  # chunk_key -> chunk_node
var _low_detail_chunks: Dictionary = {}  # chunk_key -> chunk_node
var _chunk_states: Dictionary = {}  # chunk_key -> generation state
var _loading_queue: Array = []  # Priority sorted queue
var _generation_threads: Array = []
var _chunk_data_cache: Dictionary = {}  # Cached chunk data awaiting instantiation
var _player_chunk: Vector2i = Vector2i.ZERO
var _last_player_pos: Vector2 = Vector2.ZERO

# Thread synchronization
var _thread_mutex: Mutex
var _thread_semaphore: Semaphore
var _thread_task_queue: Array = []
var _exit_thread: bool = false
var _last_load_time: int = 0

# Entity instantiation controls
var _entity_queue: Array = []  # Queue of entities waiting to be instantiated
var _pending_chunk_entities: Dictionary = {}  # chunk_key -> number of pending entities
var _next_chunk_instantiation_time: int = 0  # Time to process next chunk
var _chunk_instantiation_interval_ms: int = 200  # Wait between chunk instantiations
var _current_instantiating_chunk: String = ""  # Currently processing chunk

# Entity pools for reuse
var _entity_pools: Dictionary = {}

enum ChunkState {
	UNLOADED,
	QUEUED,
	GENERATING,
	INSTANTIATING,  # New state for chunks being instantiated
	LOW_DETAIL,
	FULL_DETAIL
}

func _ready() -> void:
	# Register self as service
	call_deferred("register_self")
	
	# Initialize threading components
	_thread_mutex = Mutex.new()
	
	# Set up for continued processing during pause
	process_mode = Node.PROCESS_MODE_ALWAYS

# Return dependencies required by this service
func get_dependencies() -> Array:
	return ["SeedManager", "EntityManager", "GridManager"]

# Initialize this service
func initialize_service() -> void:
	# Get required dependencies
	seed_manager = get_dependency("SeedManager")
	entity_manager = get_dependency("EntityManager") 
	grid_manager = get_dependency("GridManager")
	
	# Connect to SeedManager signals
	connect_to_dependency("SeedManager", "seed_changed", _on_seed_changed)
	
	# Get optional dependencies
	if has_dependency("EventManager"):
		event_manager = get_dependency("EventManager")
	
	if has_dependency("GameSettings"):
		game_settings = get_dependency("GameSettings")
		_apply_game_settings()
	
	# Find or load chunk scene if not set
	if chunk_scene == null:
		_find_chunk_scene()
	
	# Start worker threads
	_start_generation_threads()
	
	# Register to receive player position updates
	if grid_manager:
		grid_manager.connect("player_cell_changed", _on_player_cell_changed)
	
	# Mark as initialized
	_service_initialized = true
	print("WorldChunkManager: Service initialized successfully")

func _apply_game_settings() -> void:
	if not game_settings:
		return
		
	# Get chunk size from game settings
	if "grid_cell_size" in game_settings:
		chunk_size = game_settings.grid_cell_size
	
	# Apply debug toggle if available
	if "debug_mode" in game_settings and "debug_world_chunks" in game_settings:
		var debug_enabled = game_settings.debug_mode and game_settings.debug_world_chunks
		if debug_enabled:
			print("WorldChunkManager: Debug mode enabled")

func _find_chunk_scene() -> void:
	var chunk_path = "res://scenes/world/world_chunk.tscn"
	if ResourceLoader.exists(chunk_path):
		chunk_scene = load(chunk_path)
	else:
		# If not found, try to create a minimal chunk dynamically
		var script = load("res://scripts/world/world_chunk.gd")
		if script:
			var scene = PackedScene.new()
			var node = Node2D.new()
			node.set_script(script)
			var result = scene.pack(node)
			if result == OK:
				chunk_scene = scene
				print("WorldChunkManager: Created dynamic chunk scene")

func _start_generation_threads() -> void:
	# Initialize semaphore for thread synchronization
	_thread_semaphore = Semaphore.new()
	
	# Start worker threads
	for i in range(thread_count):
		var thread = Thread.new()
		thread.start(_thread_worker)
		_generation_threads.append(thread)
	
	print("WorldChunkManager: Started %d generation threads" % thread_count)

func _process(delta: float) -> void:
	# Skip if not initialized
	if not _service_initialized:
		return
	
	# Update player position if grid manager not available
	if not grid_manager:
		_update_player_position()
	
	# Process entity instantiation queue with fixed batch size
	if not _entity_queue.empty():
		var batch_count = min(entity_batch_size, _entity_queue.size())
		
		for i in range(batch_count):
			var entity_data = _entity_queue.pop_front()
			_instantiate_entity(entity_data.entity, entity_data.chunk)
			
			# Update pending entity count for this chunk
			var chunk_key = entity_data.chunk_key
			if _pending_chunk_entities.has(chunk_key):
				_pending_chunk_entities[chunk_key] -= 1
				if _pending_chunk_entities[chunk_key] <= 0:
					_pending_chunk_entities.erase(chunk_key)
					
					# If we finished all entities for a chunk, update its state
					if _chunk_states.has(chunk_key) and _chunk_states[chunk_key] == ChunkState.INSTANTIATING:
						var chunk_coords = str_to_vector2i(chunk_key)
						# Determine if it should be full or low detail
						if _get_chunk_full_detail_state(chunk_coords):
							_chunk_states[chunk_key] = ChunkState.FULL_DETAIL
						else:
							_chunk_states[chunk_key] = ChunkState.LOW_DETAIL
		
		# Exit early to maintain a consistent frame rate
		return
	
	# Process one chunk's data at a time with time controls
	var current_time = Time.get_ticks_msec()
	
	# Check if we can process another chunk
	if not _chunk_data_cache.empty() and current_time >= _next_chunk_instantiation_time:
		# Process one chunk at a time
		var next_chunk_key = _chunk_data_cache.keys()[0]
		var chunk_data = _chunk_data_cache[next_chunk_key]
		
		# Create the chunk in the main thread
		var chunk_coords = str_to_vector2i(next_chunk_key)
		_chunk_states[next_chunk_key] = ChunkState.INSTANTIATING
		_current_instantiating_chunk = next_chunk_key
		
		# Create the base chunk first (without entities)
		call_deferred("_create_base_chunk", chunk_coords, chunk_data)
		
		# Remove from cache
		_chunk_data_cache.erase(next_chunk_key)
		
		# Set the next time we can process another chunk
		_next_chunk_instantiation_time = current_time + _chunk_instantiation_interval_ms
		
		# Exit early to maintain a consistent frame rate
		return
	
	# Update distance-based detail levels for existing chunks
	_update_chunk_detail_levels()
	
	# Start new chunk loads if we have capacity
	var current_loads = 0
	for state in _chunk_states.values():
		if state == ChunkState.GENERATING:
			current_loads += 1
	
	# Check if minimum wait time has passed
	var now = Time.get_ticks_msec()
	var can_load = (now - _last_load_time) >= min_wait_between_loads_ms
	
	# Process loading queue if we have capacity and enough time has passed
	if current_loads < max_concurrent_loads and can_load and not _loading_queue.empty():
		var next_in_queue = _loading_queue.pop_front()
		var chunk_coords = next_in_queue.coords
		var chunk_key = vector2i_to_str(chunk_coords)
		
		# Start generation
		_thread_mutex.lock()
		_chunk_states[chunk_key] = ChunkState.GENERATING
		_thread_mutex.unlock()
		
		# Add task to thread queue
		_thread_mutex.lock()
		_thread_task_queue.append({
			"coords": chunk_coords
		})
		_thread_mutex.unlock()
		
		# Signal to a thread that there's work
		_thread_semaphore.post()
		
		# Remember when we last started a load
		_last_load_time = now

# Deferred method to create a base chunk without entities
func _create_base_chunk(coords: Vector2i, chunk_data: Dictionary) -> void:
	var chunk_key = vector2i_to_str(coords)
	
	# Skip if already loaded
	if _loaded_chunks.has(chunk_key) or _low_detail_chunks.has(chunk_key):
		_chunk_states[chunk_key] = ChunkState.FULL_DETAIL if _loaded_chunks.has(chunk_key) else ChunkState.LOW_DETAIL
		return
	
	# Create chunk instance
	var chunk = chunk_scene.instantiate()
	add_child(chunk)
	
	# Setup coordinates and data
	var full_detail = _get_chunk_full_detail_state(coords)
	chunk.initialize(coords, chunk_data, full_detail)
	
	# Set position based on coordinates
	chunk.global_position = Vector2(coords.x * chunk_size, coords.y * chunk_size)
	
	# Store in the appropriate dictionary
	if full_detail:
		_loaded_chunks[chunk_key] = chunk
		chunk_loaded.emit(coords, chunk)
	else:
		_low_detail_chunks[chunk_key] = chunk
		low_detail_chunk_loaded.emit(coords, chunk)
	
	print("Created base chunk at %s" % coords)
	
	# Queue entities for staggered instantiation
	_queue_entities_for_instantiation(chunk_data.entities, chunk, chunk_key)

# Queue entities for staggered instantiation
func _queue_entities_for_instantiation(entity_data_list: Array, chunk: Node, chunk_key: String) -> void:
	if entity_data_list.empty():
		# If no entities, just mark as complete
		if _chunk_states.has(chunk_key) and _chunk_states[chunk_key] == ChunkState.INSTANTIATING:
			if _get_chunk_full_detail_state(str_to_vector2i(chunk_key)):
				_chunk_states[chunk_key] = ChunkState.FULL_DETAIL
			else:
				_chunk_states[chunk_key] = ChunkState.LOW_DETAIL
		return
	
	# Track how many entities need to be processed for this chunk
	_pending_chunk_entities[chunk_key] = entity_data_list.size()
	
	# Add each entity to the queue
	for entity_data in entity_data_list:
		_entity_queue.append({
			"entity": entity_data,
			"chunk": chunk,
			"chunk_key": chunk_key
		})

func _update_player_position() -> void:
	# Find player in entity manager or scene tree
	var player = null
	
	if entity_manager:
		player = entity_manager.get_nearest_entity(Vector2.ZERO, "player")
	else:
		var players = get_tree().get_nodes_in_group("player")
		if not players.empty():
			player = players[0]
	
	if player and is_instance_valid(player):
		var player_pos = player.global_position
		
		# Only update if position changed significantly
		if player_pos.distance_to(_last_player_pos) > chunk_size / 4.0:
			_last_player_pos = player_pos
			
			# Calculate new chunk coordinates
			var new_chunk = world_to_chunk(player_pos)
			
			# If player moved to a new chunk
			if new_chunk != _player_chunk:
				var old_chunk = _player_chunk
				_player_chunk = new_chunk
				
				# Emit signal
				player_entered_chunk.emit(old_chunk, new_chunk)
				
				# Update chunk priorities
				_update_chunk_priorities()

func _update_chunk_priorities() -> void:
	# Clear current loading queue
	_loading_queue.clear()
	
	# Collect all chunk coordinates that should be loaded
	var active_chunks = []
	var preload_chunks = []
	
	# First determine which chunks should be loaded (full detail)
	for x in range(_player_chunk.x - active_chunk_distance, _player_chunk.x + active_chunk_distance + 1):
		for y in range(_player_chunk.y - active_chunk_distance, _player_chunk.y + active_chunk_distance + 1):
			var coords = Vector2i(x, y)
			active_chunks.append(coords)
	
	# Then determine which chunks should be preloaded (low detail)
	for x in range(_player_chunk.x - preload_chunk_distance, _player_chunk.x + preload_chunk_distance + 1):
		for y in range(_player_chunk.y - preload_chunk_distance, _player_chunk.y + preload_chunk_distance + 1):
			var coords = Vector2i(x, y)
			if not coords in active_chunks:
				preload_chunks.append(coords)
	
	# Queue active chunks for loading if they're not already loaded
	for coords in active_chunks:
		var chunk_key = vector2i_to_str(coords)
		
		if not _chunk_states.has(chunk_key) or _chunk_states[chunk_key] == ChunkState.UNLOADED:
			_loading_queue.append({
				"coords": coords,
				"priority": 0,  # Highest priority
				"full_detail": true
			})
			_chunk_states[chunk_key] = ChunkState.QUEUED
		elif _chunk_states[chunk_key] == ChunkState.LOW_DETAIL:
			# Upgrade low detail to full detail
			_loading_queue.append({
				"coords": coords,
				"priority": 1,  # Medium priority
				"full_detail": true
			})
			_chunk_states[chunk_key] = ChunkState.QUEUED
	
	# Queue preload chunks for loading if they're not already loaded or preloaded
	for coords in preload_chunks:
		var chunk_key = vector2i_to_str(coords)
		
		if not _chunk_states.has(chunk_key) or _chunk_states[chunk_key] == ChunkState.UNLOADED:
			_loading_queue.append({
				"coords": coords,
				"priority": 2,  # Lowest priority
				"full_detail": false
			})
			_chunk_states[chunk_key] = ChunkState.QUEUED
	
	# Find chunks to unload (beyond despawn distance)
	var unload_keys = []
	for chunk_key in _loaded_chunks.keys():
		var chunk_coords = str_to_vector2i(chunk_key)
		var distance = (_player_chunk - chunk_coords).length()
		
		if distance > despawn_distance:
			unload_keys.append(chunk_key)
	
	# Unload distant chunks
	for chunk_key in unload_keys:
		var chunk_coords = str_to_vector2i(chunk_key)
		unload_chunk(chunk_coords)
	
	# Also check low detail chunks
	unload_keys = []
	for chunk_key in _low_detail_chunks.keys():
		var chunk_coords = str_to_vector2i(chunk_key)
		var distance = (_player_chunk - chunk_coords).length()
		
		if distance > despawn_distance:
			unload_keys.append(chunk_key)
	
	# Unload distant low detail chunks
	for chunk_key in unload_keys:
		var chunk_coords = str_to_vector2i(chunk_key)
		unload_low_detail_chunk(chunk_coords)
	
	# Sort loading queue by priority (then by distance)
	_sort_loading_queue()

func _update_chunk_detail_levels() -> void:
	# Check full detail chunks that might need to be downgraded
	var chunks_to_downgrade = []
	
	for chunk_key in _loaded_chunks.keys():
		var chunk_coords = str_to_vector2i(chunk_key)
		var distance = (_player_chunk - chunk_coords).length()
		
		# If chunk is now beyond active distance but within preload distance
		if distance > active_chunk_distance and distance <= preload_chunk_distance:
			chunks_to_downgrade.append(chunk_coords)
	
	# Downgrade chunks to low detail
	for coords in chunks_to_downgrade:
		_downgrade_chunk_to_low_detail(coords)
	
	# Check low detail chunks that might need to be upgraded
	var chunks_to_upgrade = []
	
	for chunk_key in _low_detail_chunks.keys():
		var chunk_coords = str_to_vector2i(chunk_key)
		var distance = (_player_chunk - chunk_coords).length()
		
		# If chunk is now within active distance
		if distance <= active_chunk_distance:
			chunks_to_upgrade.append(chunk_coords)
	
	# Upgrade chunks to full detail
	for coords in chunks_to_upgrade:
		_upgrade_chunk_to_full_detail(coords)

func _downgrade_chunk_to_low_detail(coords: Vector2i) -> void:
	var chunk_key = vector2i_to_str(coords)
	
	# Skip if not loaded or already low detail
	if not _loaded_chunks.has(chunk_key):
		return
	
	var chunk = _loaded_chunks[chunk_key]
	
	# Mark chunk as low detail
	if chunk.has_method("set_detail_level"):
		chunk.set_detail_level(false)
	
	# Move to low detail dictionary
	_low_detail_chunks[chunk_key] = chunk
	_loaded_chunks.erase(chunk_key)
	_chunk_states[chunk_key] = ChunkState.LOW_DETAIL
	
	print("Downgraded chunk %s to low detail" % coords)

func _upgrade_chunk_to_full_detail(coords: Vector2i) -> void:
	var chunk_key = vector2i_to_str(coords)
	
	# Skip if not in low detail
	if not _low_detail_chunks.has(chunk_key):
		return
	
	var chunk = _low_detail_chunks[chunk_key]
	
	# Mark chunk as full detail
	if chunk.has_method("set_detail_level"):
		chunk.set_detail_level(true)
	
	# Move to full detail dictionary
	_loaded_chunks[chunk_key] = chunk
	_low_detail_chunks.erase(chunk_key)
	_chunk_states[chunk_key] = ChunkState.FULL_DETAIL
	
	print("Upgraded chunk %s to full detail" % coords)

func _sort_loading_queue() -> void:
	# Sort by priority first, then by distance to player
	_loading_queue.sort_custom(func(a, b):
		# First compare priority
		if a.priority != b.priority:
			return a.priority < b.priority
		
		# If same priority, compare distance to player
		var a_dist = (_player_chunk - a.coords).length()
		var b_dist = (_player_chunk - b.coords).length()
		
		return a_dist < b_dist
	)

func _thread_worker() -> void:
	while true:
		# Wait for a task to be available
		_thread_semaphore.wait()
		
		# Check if we should exit
		_thread_mutex.lock()
		if _exit_thread:
			_thread_mutex.unlock()
			break
		
		# Get a task from the queue
		var task = null
		if not _thread_task_queue.empty():
			task = _thread_task_queue.pop_front()
		_thread_mutex.unlock()
		
		# If no task, continue waiting
		if not task:
			continue
		
		# Process the task
		var chunk_coords = task.coords
		
		# Generate chunk data
		var chunk_data = _generate_chunk_data(chunk_coords)
		
		# Queue the data for the main thread to instantiate
		var chunk_key = vector2i_to_str(chunk_coords)
		_thread_mutex.lock()
		_chunk_data_cache[chunk_key] = chunk_data
		_thread_mutex.unlock()

func _generate_chunk_data(coords: Vector2i) -> Dictionary:
	# Generate a deterministic seed for this chunk
	var chunk_id = _get_chunk_id(coords)
	
	var data = {
		"entities": [],
		"background": {
			"type": 0,
			"density": 0.5
		}
	}
	
	# Use SeedManager for deterministic generation if available
	if seed_manager:
		data.background.type = seed_manager.get_random_int(chunk_id, 0, 3)
		data.background.density = seed_manager.get_random_value(chunk_id + 1, 0.1, 1.0)
		
		# Determine entity count (asteroids, debris, etc)
		var entity_count = seed_manager.get_random_int(chunk_id + 2, 5, 20)
		
		# Generate entities
		for i in range(entity_count):
			var entity_id = chunk_id + (i * 100)
			
			# Entity type determination
			var entity_type = "asteroid"
			var type_roll = seed_manager.get_random_value(entity_id, 0, 1)
			
			if type_roll > 0.9:
				entity_type = "enemy_ship"
			elif type_roll > 0.8:
				entity_type = "debris"
			
			# Entity position within chunk
			var pos_x = seed_manager.get_random_value(entity_id + 1, 0, chunk_size)
			var pos_y = seed_manager.get_random_value(entity_id + 2, 0, chunk_size)
			
			var world_x = (coords.x * chunk_size) + pos_x
			var world_y = (coords.y * chunk_size) + pos_y
			
			# Entity rotation
			var rotation = seed_manager.get_random_value(entity_id + 3, 0, TAU)
			
			# Entity size/scale variation
			var scale = seed_manager.get_random_value(entity_id + 4, 0.5, 1.5)
			
			# Add to entity list
			data.entities.append({
				"type": entity_type,
				"id": entity_id,
				"position": Vector2(world_x, world_y),
				"rotation": rotation,
				"scale": scale
			})
	else:
		# Fallback to simpler randomization if SeedManager not available
		var rng = RandomNumberGenerator.new()
		rng.seed = chunk_id
		
		data.background.type = rng.randi_range(0, 3)
		data.background.density = rng.randf_range(0.1, 1.0)
		
		# Basic entity generation
		var entity_count = rng.randi_range(5, 20)
		for i in range(entity_count):
			var entity_id = chunk_id + (i * 100)
			
			# Simple entity data
			var entity_type = "asteroid"
			if rng.randf() > 0.8:
				entity_type = "enemy_ship"
			
			var pos_x = rng.randf() * chunk_size
			var pos_y = rng.randf() * chunk_size
			
			var world_x = (coords.x * chunk_size) + pos_x
			var world_y = (coords.y * chunk_size) + pos_y
			
			data.entities.append({
				"type": entity_type,
				"id": entity_id,
				"position": Vector2(world_x, world_y),
				"rotation": rng.randf() * TAU,
				"scale": rng.randf_range(0.5, 1.5)
			})
	
	return data

# Instantiate single entity with deferred calls
func _instantiate_entity(entity_data: Dictionary, chunk: Node) -> void:
	var entity_type = entity_data.type
	var entity_id = entity_data.id
	var position = entity_data.position
	var rotation = entity_data.rotation
	var scale_factor = entity_data.get("scale", 1.0)
	
	# Get entity from pool or create new
	var entity = _get_entity_from_pool(entity_type)
	
	if entity:
		# Configure the entity
		entity.global_position = position
		entity.rotation = rotation
		
		# Set scale if supported
		if entity.has_method("set_scale"):
			entity.set_scale(Vector2(scale_factor, scale_factor))
		elif entity is Node2D:
			entity.scale = Vector2(scale_factor, scale_factor)
		
		# Set entity ID if supported
		if entity.get("entity_id") != null:
			entity.entity_id = entity_id
		else:
			entity.set_meta("entity_id", entity_id)
		
		# Add entity to chunk - use call_deferred for thread safety
		chunk.call_deferred("add_entity", entity)
		
		# Register with EntityManager if available
		if entity_manager and entity_manager.has_method("register_entity"):
			entity_manager.call_deferred("register_entity", entity, entity_type)

func _get_entity_from_pool(entity_type: String) -> Node:
	# Create pools if they don't exist
	if not _entity_pools.has(entity_type):
		_entity_pools[entity_type] = []
	
	# Check if we have a free entity in the pool
	if not _entity_pools[entity_type].empty():
		return _entity_pools[entity_type].pop_back()
	
	# Otherwise create a new entity
	var entity_scene = _get_entity_scene(entity_type)
	if entity_scene:
		var entity = entity_scene.instantiate()
		entity.set_meta("entity_type", entity_type)
		return entity
	
	# Fallback to a simple placeholder if scene not found
	var placeholder = Sprite2D.new()
	placeholder.name = "Placeholder_%s" % entity_type
	placeholder.set_meta("entity_type", entity_type)
	placeholder.set_meta("is_placeholder", true)
	
	# Try to set a basic texture
	var texture_path = "res://assets/placeholder_%s.png" % entity_type
	if ResourceLoader.exists(texture_path):
		placeholder.texture = load(texture_path)
	
	return placeholder

func _get_entity_scene(entity_type: String) -> PackedScene:
	# Try to find the entity scene
	var potential_paths = [
		"res://scenes/entities/%s.tscn" % entity_type,
		"res://scenes/entities/%ss/%s.tscn" % [entity_type, entity_type],
		"res://scenes/world/%s.tscn" % entity_type
	]
	
	for path in potential_paths:
		if ResourceLoader.exists(path):
			return load(path)
	
	return null

func _return_entity_to_pool(entity: Node) -> void:
	# Skip if entity not valid
	if not is_instance_valid(entity):
		return
	
	# Get entity type
	var entity_type = entity.get_meta("entity_type", "unknown")
	
	# Skip placeholders
	if entity.get_meta("is_placeholder", false):
		entity.queue_free()
		return
	
	# Create pool if it doesn't exist
	if not _entity_pools.has(entity_type):
		_entity_pools[entity_type] = []
	
	# Remove from current parent
	if entity.get_parent():
		entity.get_parent().remove_child(entity)
	
	# Reset entity state if it has a reset method
	if entity.has_method("reset"):
		entity.reset()
	
	# Add to pool
	_entity_pools[entity_type].append(entity)

# Public API methods

# Load a chunk at specified coordinates
func load_chunk(coords: Vector2i, full_detail: bool = true) -> void:
	var chunk_key = vector2i_to_str(coords)
	
	# Skip if already loaded or in process
	if _loaded_chunks.has(chunk_key) or _low_detail_chunks.has(chunk_key) or \
	   (_chunk_states.has(chunk_key) and (_chunk_states[chunk_key] == ChunkState.QUEUED or 
	   _chunk_states[chunk_key] == ChunkState.GENERATING or 
	   _chunk_states[chunk_key] == ChunkState.INSTANTIATING)):
		return
	
	# Add to loading queue with appropriate priority
	var priority = 0 if full_detail else 2
	_loading_queue.append({
		"coords": coords,
		"priority": priority,
		"full_detail": full_detail
	})
	
	# Mark as queued
	_chunk_states[chunk_key] = ChunkState.QUEUED
	
	# Resort queue
	_sort_loading_queue()

# Unload a chunk at specified coordinates
func unload_chunk(coords: Vector2i) -> void:
	var chunk_key = vector2i_to_str(coords)
	
	# Skip if not loaded
	if not _loaded_chunks.has(chunk_key):
		return
	
	var chunk = _loaded_chunks[chunk_key]
	
	# Return entities to pool
	var entities = chunk.get_entities()
	for entity in entities:
		# Deregister from EntityManager if available
		if entity_manager and entity_manager.has_method("deregister_entity"):
			entity_manager.deregister_entity(entity)
		
		# Return to pool
		_return_entity_to_pool(entity)
	
	# Remove chunk
	_loaded_chunks.erase(chunk_key)
	chunk.queue_free()
	
	# Update state
	_chunk_states[chunk_key] = ChunkState.UNLOADED
	
	# Emit signal
	chunk_unloaded.emit(coords)
	
	print("Unloaded chunk at %s" % coords)

# Unload a low detail chunk
func unload_low_detail_chunk(coords: Vector2i) -> void:
	var chunk_key = vector2i_to_str(coords)
	
	# Skip if not in low detail
	if not _low_detail_chunks.has(chunk_key):
		return
	
	var chunk = _low_detail_chunks[chunk_key]
	
	# Return entities to pool
	var entities = chunk.get_entities()
	for entity in entities:
		# Deregister from EntityManager if available
		if entity_manager and entity_manager.has_method("deregister_entity"):
			entity_manager.deregister_entity(entity)
		
		# Return to pool
		_return_entity_to_pool(entity)
	
	# Remove chunk
	_low_detail_chunks.erase(chunk_key)
	chunk.queue_free()
	
	# Update state
	_chunk_states[chunk_key] = ChunkState.UNLOADED
	
	# Emit signal
	chunk_unloaded.emit(coords)
	
	print("Unloaded low detail chunk at %s" % coords)

# Check if a chunk is loaded (either full or low detail)
func is_chunk_loaded(coords: Vector2i) -> bool:
	var chunk_key = vector2i_to_str(coords)
	return _loaded_chunks.has(chunk_key) or _low_detail_chunks.has(chunk_key)

# Get the chunk node at coordinates
func get_chunk(coords: Vector2i) -> Node:
	var chunk_key = vector2i_to_str(coords)
	
	if _loaded_chunks.has(chunk_key):
		return _loaded_chunks[chunk_key]
	
	if _low_detail_chunks.has(chunk_key):
		return _low_detail_chunks[chunk_key]
	
	return null

# Get the current state of a chunk
func get_chunk_state(coords: Vector2i) -> int:
	var chunk_key = vector2i_to_str(coords)
	
	if not _chunk_states.has(chunk_key):
		return ChunkState.UNLOADED
	
	return _chunk_states[chunk_key]

# Load world chunks around a given position
func load_chunks_around_position(position: Vector2, full_detail_range: int = 2, low_detail_range: int = 4) -> void:
	var center_chunk = world_to_chunk(position)
	
	# Queue chunks for loading
	for x in range(center_chunk.x - low_detail_range, center_chunk.x + low_detail_range + 1):
		for y in range(center_chunk.y - low_detail_range, center_chunk.y + low_detail_range + 1):
			var coords = Vector2i(x, y)
			var distance = (center_chunk - coords).length()
			
			if distance <= full_detail_range:
				load_chunk(coords, true)  # Full detail
			elif distance <= low_detail_range:
				load_chunk(coords, false)  # Low detail

# Reset the chunk manager
func reset() -> void:
	# Clear entity queue and pending chunks
	_entity_queue.clear()
	_pending_chunk_entities.clear()
	
	# Unload all chunks
	var loaded_keys = _loaded_chunks.keys()
	for chunk_key in loaded_keys:
		var coords = str_to_vector2i(chunk_key)
		unload_chunk(coords)
	
	var low_detail_keys = _low_detail_chunks.keys()
	for chunk_key in low_detail_keys:
		var coords = str_to_vector2i(chunk_key)
		unload_low_detail_chunk(coords)
	
	# Clear all tracking
	_loading_queue.clear()
	_chunk_states.clear()
	_chunk_data_cache.clear()
	
	# Reset player position tracking
	_player_chunk = Vector2i.ZERO
	_last_player_pos = Vector2.ZERO
	
	print("WorldChunkManager: Reset complete")

# Utility functions

# Convert world position to chunk coordinates
func world_to_chunk(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / chunk_size)),
		int(floor(world_pos.y / chunk_size))
	)

# Convert chunk coordinates to world position (chunk center)
func chunk_to_world(chunk_coords: Vector2i) -> Vector2:
	return Vector2(
		(chunk_coords.x * chunk_size) + (chunk_size / 2),
		(chunk_coords.y * chunk_size) + (chunk_size / 2)
	)

# Convert Vector2i to string key
func vector2i_to_str(vec: Vector2i) -> String:
	return "%d,%d" % [vec.x, vec.y]

# Convert string key to Vector2i
func str_to_vector2i(str_key: String) -> Vector2i:
	var parts = str_key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))

# Generate a deterministic chunk ID based on coordinates
func _get_chunk_id(coords: Vector2i) -> int:
	# Base seed from SeedManager or GameSettings
	var base_seed = 0
	if seed_manager:
		base_seed = seed_manager.get_seed()
	elif game_settings and game_settings.has_method("get_seed"):
		base_seed = game_settings.get_seed()
	else:
		base_seed = 12345  # Fallback
	
	# Use prime multipliers to avoid patterns
	return base_seed + (coords.x * 7919) + (coords.y * 6337)

# Determine if a chunk should be full detail based on distance from player
func _get_chunk_full_detail_state(coords: Vector2i) -> bool:
	var distance = (_player_chunk - coords).length()
	return distance <= active_chunk_distance

# Handle player cell changes from GridManager
func _on_player_cell_changed(old_cell: Vector2i, new_cell: Vector2i) -> void:
	_player_chunk = new_cell
	_update_chunk_priorities()

# Handle seed changes from SeedManager
func _on_seed_changed(new_seed: int) -> void:
	# Regenerate all loaded chunks
	# This is resource intensive but ensures world consistency
	
	# Stop all current loading
	_loading_queue.clear()
	_chunk_data_cache.clear()
	_entity_queue.clear()
	_pending_chunk_entities.clear()
	
	# Remember which chunks were loaded
	var loaded_chunks = _loaded_chunks.keys().duplicate()
	var low_detail_chunks = _low_detail_chunks.keys().duplicate()
	
	# Unload all chunks
	for chunk_key in loaded_chunks:
		var coords = str_to_vector2i(chunk_key)
		unload_chunk(coords)
	
	for chunk_key in low_detail_chunks:
		var coords = str_to_vector2i(chunk_key)
		unload_low_detail_chunk(coords)
	
	# Reload the chunks
	for chunk_key in loaded_chunks:
		var coords = str_to_vector2i(chunk_key)
		load_chunk(coords, true)
	
	for chunk_key in low_detail_chunks:
		var coords = str_to_vector2i(chunk_key)
		load_chunk(coords, false)
	
	print("WorldChunkManager: Regenerating all chunks due to seed change")

# Clean up threads when scene exits
func _exit_tree() -> void:
	# Signal threads to exit
	_thread_mutex.lock()
	_exit_thread = true
	_thread_mutex.unlock()
	
	# Post to semaphore for each thread to ensure they all wake up
	for i in range(_generation_threads.size()):
		_thread_semaphore.post()
	
	# Wait for threads to finish
	for thread in _generation_threads:
		if thread is Thread and thread.is_started():
			thread.wait_to_finish()
