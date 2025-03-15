extends Node
class_name ObjectPool

# ObjectPool signals
signal object_created(object)
signal object_retrieved(object)
signal object_returned(object)
signal pool_resized(new_size)

# Configuration
@export var scene_path: String = ""
@export var initial_pool_size: int = 10
@export var max_pool_size: int = 50
@export var auto_expand: bool = true
@export var expand_step: int = 5
@export var debug_mode: bool = false
@export var node_parent_path: NodePath = NodePath(".")

# Pool state
var _pool: Array = []
var _active_objects: Array = []
var _scene_resource = null
var _node_parent: Node = null
var _pool_initialized: bool = false

func _ready() -> void:
	# Get the parent node for pool objects
	_node_parent = get_node_or_null(node_parent_path)
	if not _node_parent:
		_node_parent = self
	
	# If scene_path is provided, initialize immediately
	if not scene_path.is_empty():
		initialize(scene_path, initial_pool_size)

# Initialize the pool with a scene
func initialize(scene_path: String, size: int = 0) -> void:
	# Clean up any existing pool
	clear()
	
	if debug_mode:
		print("ObjectPool: Initializing with scene ", scene_path)
	
	# Load the scene
	if not ResourceLoader.exists(scene_path):
		push_error("ObjectPool: Scene does not exist: " + scene_path)
		return
	
	_scene_resource = load(scene_path)
	
	# Set initial size
	if size > 0:
		resize(size)
	
	_pool_initialized = true

# Create a new object for the pool
func _create_object() -> Node:
	if not _scene_resource:
		push_error("ObjectPool: Scene resource not loaded")
		return null
	
	var object = _scene_resource.instantiate()
	if not object:
		push_error("ObjectPool: Failed to instantiate object")
		return null
	
	_node_parent.add_child(object)
	_prepare_for_pool(object)
	
	object_created.emit(object)
	return object

# Prepare an object for storage in the pool
func _prepare_for_pool(object: Node) -> void:
	# Disable processing and visibility
	if object is Node2D:
		object.visible = false
	
	if object is CanvasItem:
		object.set_process(false)
		object.set_physics_process(false)
		object.set_process_input(false)
		object.set_process_unhandled_input(false)
		object.set_process_unhandled_key_input(false)
	
	# Clear collision if applicable
	if "collision_layer" in object:
		object.set_meta("_pool_collision_layer", object.collision_layer)
		object.set_meta("_pool_collision_mask", object.collision_mask)
		object.collision_layer = 0
		object.collision_mask = 0
	
	# Reset object state if it has a reset method
	if object.has_method("reset_for_pool"):
		object.reset_for_pool()
	
	# Set metadata
	object.set_meta("_pooled", true)

# Restore an object for active use
func _prepare_for_use(object: Node) -> void:
	# Re-enable processing and visibility
	if object is Node2D:
		object.visible = true
	
	if object is CanvasItem:
		object.set_process(true)
		object.set_physics_process(true)
		object.set_process_input(true)
	
	# Restore collision if applicable
	if "collision_layer" in object and object.has_meta("_pool_collision_layer"):
		object.collision_layer = object.get_meta("_pool_collision_layer")
		object.collision_mask = object.get_meta("_pool_collision_mask")
	
	# Initialize object if it has an initialize method
	if object.has_method("initialize_from_pool"):
		object.initialize_from_pool()
	
	# Clear pooled metadata
	object.set_meta("_pooled", false)

# Get an object from the pool
func get_object() -> Node:
	if not _pool_initialized:
		push_error("ObjectPool: Pool not initialized")
		return null
	
	# Check if we need to expand the pool
	if _pool.is_empty() and auto_expand and _pool.size() + _active_objects.size() < max_pool_size:
		if debug_mode:
			print("ObjectPool: Auto-expanding pool by ", expand_step, " objects")
		var objects_to_add = min(expand_step, max_pool_size - _pool.size() - _active_objects.size())
		if objects_to_add > 0:
			resize(_pool.size() + _active_objects.size() + objects_to_add)
	
	# Get an object from the pool
	var object = null
	if not _pool.is_empty():
		object = _pool.pop_back()
		_prepare_for_use(object)
	else:
		if debug_mode:
			print("ObjectPool: Pool empty, creating new object outside pool")
		# Create a new object if we can't expand
		object = _create_object()
		_prepare_for_use(object)
	
	# Track active objects
	_active_objects.append(object)
	
	# Connect tree_exiting signal if not already connected
	if not object.tree_exiting.is_connected(_on_object_tree_exiting):
		object.tree_exiting.connect(_on_object_tree_exiting.bind(object))
	
	object_retrieved.emit(object)
	return object

# Return an object to the pool
func return_object(object: Node) -> void:
	if not object:
		return
	
	# Check if object is already in the pool
	if object.has_meta("_pooled") and object.get_meta("_pooled"):
		return
	
	# Check if we have room in the pool
	if _pool.size() >= max_pool_size:
		if debug_mode:
			print("ObjectPool: Pool full, destroying object")
		object.queue_free()
		return
	
	# Remove from active objects
	var index = _active_objects.find(object)
	if index >= 0:
		_active_objects.remove_at(index)
	
	# Prepare for pooling
	_prepare_for_pool(object)
	
	# Add to pool
	_pool.append(object)
	
	object_returned.emit(object)

# Handle objects being deleted
func _on_object_tree_exiting(object: Node) -> void:
	var index = _active_objects.find(object)
	if index >= 0:
		_active_objects.remove_at(index)

# Resize the pool
func resize(new_size: int) -> void:
	new_size = clamp(new_size, 0, max_pool_size)
	
	var current_size = _pool.size()
	
	if new_size > current_size:
		# Grow the pool
		for i in range(new_size - current_size):
			var object = _create_object()
			if object:
				_pool.append(object)
	elif new_size < current_size:
		# Shrink the pool
		while _pool.size() > new_size:
			var object = _pool.pop_back()
			object.queue_free()
	
	if debug_mode:
		print("ObjectPool: Resized to ", _pool.size(), " objects")
	
	pool_resized.emit(_pool.size())

# Get the current pool size
func get_pool_size() -> int:
	return _pool.size()

# Get the number of active objects
func get_active_count() -> int:
	return _active_objects.size()

# Get the total number of objects (pooled + active)
func get_total_count() -> int:
	return _pool.size() + _active_objects.size()

# Clear the entire pool
func clear() -> void:
	# Clear the pool objects
	for object in _pool:
		if is_instance_valid(object):
			object.queue_free()
	
	_pool.clear()
	
	# Note: We don't clear active objects as they might still be in use
	
	if debug_mode:
		print("ObjectPool: Pool cleared")
