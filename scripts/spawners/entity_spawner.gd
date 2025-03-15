extends Node
class_name EntitySpawner

# Signals for lifecycle events
signal entity_spawned(entity, entity_data)
signal entity_despawned(entity, entity_data)
signal entity_restored(entity, entity_data)

# Pooling configuration
@export_category("Pooling")
@export var use_object_pooling: bool = true
@export var initial_pool_size: int = 5
@export var max_pool_size: int = 20
@export var grow_pool_by: int = 5

# Spawning configuration
@export_category("Spawning")
@export var auto_register_with_entity_manager: bool = true
@export var entity_type: String = "entity"
@export var scene_path: String = ""

# Debug settings
@export_category("Debug")
@export var debug_spawning: bool = false
@export var debug_pooling: bool = false

# Entity and pool tracking
var _entity_map: Dictionary = {}    # Maps entity_id to spawned entity
var _data_map: Dictionary = {}      # Maps entity_id to entity_data
var _inactive_pool: Array = []      # Available entities
var _scene_cache = null             # Cached scene resource

# Manager references
var _entity_manager = null
var _game_settings = null
var _seed_manager = null

func _ready() -> void:
	# Initialize references to managers
	_entity_manager = get_node_or_null("/root/EntityManager")
	_seed_manager = get_node_or_null("/root/SeedManager")
	
	var main_scene = get_tree().current_scene
	_game_settings = main_scene.get_node_or_null("GameSettings")
	
	# Load the entity scene 
	if not scene_path.is_empty():
		_load_scene()
	
	# Create initial pool if configured to do so
	if use_object_pooling and initial_pool_size > 0:
		_initialize_pool(initial_pool_size)

# Pre-load the scene resource
func _load_scene() -> void:
	if not ResourceLoader.exists(scene_path):
		push_error("EntitySpawner: Scene path does not exist: " + scene_path)
		return
	
	_scene_cache = load(scene_path)
	
	if debug_spawning:
		print("EntitySpawner: Loaded scene: ", scene_path)

# Initialize the object pool with a given size
func _initialize_pool(size: int) -> void:
	if _scene_cache == null:
		_load_scene()
		
	if _scene_cache == null:
		push_error("EntitySpawner: Can't initialize pool, scene not loaded")
		return
	
	for i in range(size):
		var entity = _scene_cache.instantiate()
		if entity:
			entity.name = entity_type + "_pooled_" + str(i)
			add_child(entity)
			_prepare_entity_for_pool(entity)
			_inactive_pool.append(entity)
	
	if debug_pooling:
		print("EntitySpawner: Initialized pool with ", size, " entities of type ", entity_type)

# Prepare an entity for storage in the pool
func _prepare_entity_for_pool(entity: Node) -> void:
	# Set entity to inactive state
	if entity is Node2D:
		entity.visible = false
		entity.process_mode = Node.PROCESS_MODE_DISABLED
		
		# Hide from collision layers if it has them
		if "collision_layer" in entity:
			entity.set_meta("_pool_collision_layer", entity.collision_layer)
			entity.set_meta("_pool_collision_mask", entity.collision_mask)
			entity.collision_layer = 0
			entity.collision_mask = 0
	
	# Clear any runtime data the entity might have
	if entity.has_method("reset_for_pool"):
		entity.reset_for_pool()
		
	# Ensure it's properly parented
	if entity.get_parent() != self:
		if entity.get_parent():
			entity.get_parent().remove_child(entity)
		add_child(entity)
		
	# Store the fact it's pooled
	entity.set_meta("_pooled", true)

# Restore an entity from the pool to active state
func _restore_entity_from_pool(entity: Node) -> void:
	# Restore visibility and processing
	if entity is Node2D:
		entity.visible = true
		entity.process_mode = Node.PROCESS_MODE_INHERIT
		
		# Restore collision settings
		if entity.has_meta("_pool_collision_layer"):
			entity.collision_layer = entity.get_meta("_pool_collision_layer")
			entity.collision_mask = entity.get_meta("_pool_collision_mask")
	
	# Initialize for active use
	if entity.has_method("initialize_from_pool"):
		entity.initialize_from_pool()
	
	# Mark as active
	entity.set_meta("_pooled", false)

# Get an entity from the pool or instantiate a new one
func _get_entity() -> Node:
	# Check if we have inactive entities in the pool
	if use_object_pooling and not _inactive_pool.is_empty():
		var entity = _inactive_pool.pop_back()
		_restore_entity_from_pool(entity)
		
		if debug_pooling:
			print("EntitySpawner: Reused entity from pool, remaining: ", _inactive_pool.size())
			
		return entity
	
	# No pooled entity available, instantiate a new one
	if _scene_cache == null:
		_load_scene()
		
	if _scene_cache == null:
		push_error("EntitySpawner: Can't instantiate entity, scene not loaded")
		return null
	
	var entity = _scene_cache.instantiate()
	add_child(entity)
	
	if debug_spawning:
		print("EntitySpawner: Instantiated new entity of type ", entity_type)
		
	return entity

# Return an entity to the pool
func _return_entity_to_pool(entity: Node) -> void:
	if not use_object_pooling or _inactive_pool.size() >= max_pool_size:
		# If we're not using pooling or pool is full, just free the entity
		if entity.has_method("cleanup"):
			entity.cleanup()
			
		entity.queue_free()
		return
	
	# Prepare the entity for the pool
	_prepare_entity_for_pool(entity)
	
	# Add to pool
	_inactive_pool.append(entity)
	
	if debug_pooling:
		print("EntitySpawner: Returned entity to pool, pool size now: ", _inactive_pool.size())

# Main public spawning API method
func spawn_entity(entity_data) -> Node:
	if not _validate_entity_data(entity_data):
		return null
	
	# Get an entity instance (from pool or newly created)
	var entity = _get_entity()
	if not entity:
		return null
	
	# Track the entity
	var entity_id = entity_data.entity_id
	_entity_map[entity_id] = entity
	_data_map[entity_id] = entity_data
	
	# Position the entity
	if entity is Node2D and "world_position" in entity_data:
		entity.global_position = entity_data.world_position
	
	# Setup entity with data
	_configure_entity(entity, entity_data)
	
	# Register with EntityManager if needed
	if auto_register_with_entity_manager and _entity_manager and _entity_manager.has_method("register_entity"):
		_entity_manager.register_entity(entity, entity_type)
	
	# Emit signal
	entity_spawned.emit(entity, entity_data)
	
	return entity

# Despawn an entity by ID
func despawn_entity(entity_id: int) -> void:
	if not _entity_map.has(entity_id):
		return
	
	var entity = _entity_map[entity_id]
	var entity_data = _data_map[entity_id]
	
	# Deregister with EntityManager
	if auto_register_with_entity_manager and _entity_manager and _entity_manager.has_method("deregister_entity"):
		_entity_manager.deregister_entity(entity)
	
	# Emit signal
	entity_despawned.emit(entity, entity_data)
	
	# Remove from tracking
	_entity_map.erase(entity_id)
	_data_map.erase(entity_id)
	
	# Return to pool
	_return_entity_to_pool(entity)

# Despawn all entities
func despawn_all() -> void:
	var entity_ids = _entity_map.keys().duplicate()
	
	for entity_id in entity_ids:
		despawn_entity(entity_id)

# Despawn an entity by reference
func despawn_entity_by_reference(entity: Node) -> void:
	for entity_id in _entity_map:
		if _entity_map[entity_id] == entity:
			despawn_entity(entity_id)
			return

# Handle an entity's tree_exiting signal
func _on_entity_tree_exiting(entity: Node) -> void:
	despawn_entity_by_reference(entity)

# Check if an entity exists
func has_entity(entity_id: int) -> bool:
	return _entity_map.has(entity_id)

# Get an entity by ID
func get_entity(entity_id: int) -> Node:
	return _entity_map.get(entity_id)

# Get entity data by ID
func get_entity_data(entity_id: int):
	return _data_map.get(entity_id)

# Get all spawned entities
func get_all_entities() -> Array:
	return _entity_map.values()

# Get current pool size
func get_pool_size() -> int:
	return _inactive_pool.size()

# Adjust pool size
func set_pool_size(new_size: int) -> void:
	new_size = clamp(new_size, 0, max_pool_size)
	
	# Grow the pool if needed
	while _inactive_pool.size() < new_size:
		var entity = _scene_cache.instantiate()
		add_child(entity)
		_prepare_entity_for_pool(entity)
		_inactive_pool.append(entity)
	
	# Shrink the pool if needed
	while _inactive_pool.size() > new_size:
		var entity = _inactive_pool.pop_back()
		entity.queue_free()
	
	if debug_pooling:
		print("EntitySpawner: Pool size adjusted to ", _inactive_pool.size())

# Override these methods in derived classes
func _validate_entity_data(entity_data) -> bool:
	# Verify that the data is valid for this spawner
	# At minimum, check if entity_id exists
	if not "entity_id" in entity_data:
		push_error("EntitySpawner: Invalid entity data, missing entity_id")
		return false
	return true

func _configure_entity(entity: Node, entity_data) -> void:
	# Configure the entity based on the data
	# To be overridden by specialized spawners
	if entity.has_method("configure_from_data"):
		entity.configure_from_data(entity_data)
	
	# Autoconnect tree_exiting signal
	if not entity.tree_exiting.is_connected(_on_entity_tree_exiting):
		entity.tree_exiting.connect(_on_entity_tree_exiting.bind(entity))

# Destroy the spawner and all entities
func cleanup() -> void:
	# Despawn all active entities
	despawn_all()
	
	# Free all pooled entities
	for entity in _inactive_pool:
		entity.queue_free()
	
	_inactive_pool.clear()
