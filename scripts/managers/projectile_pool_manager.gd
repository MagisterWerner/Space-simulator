# scripts/managers/projectile_pool_manager.gd
extends Node
class_name ProjectilePoolManager

signal pools_initialized

# Pool configuration
@export_group("Pool Configuration")
@export var laser_pool_size: int = 30
@export var missile_pool_size: int = 15
@export var enemy_projectile_pool_size: int = 40
@export var auto_expand_pools: bool = true

# Projectile scene paths
const LASER_PROJECTILE_PATH = "res://scenes/projectiles/laser_projectile.tscn"
const MISSILE_PROJECTILE_PATH = "res://scenes/projectiles/missile_projectile.tscn"
const ENEMY_PROJECTILE_PATH = "res://scenes/projectiles/enemy_projectile.tscn"

# Projectile pools
var _projectile_pools = {}
var _active_projectiles = []

# Initialization tracking
var _initialized: bool = false
var _initializing: bool = false

# Cache for projectile scenes
var _scene_cache = {}

# Debug mode
var _debug_mode: bool = false
var _entity_manager = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	
	# Find GameSettings
	var main_scene = get_tree().current_scene
	var game_settings = main_scene.get_node_or_null("GameSettings")
	if game_settings:
		_debug_mode = game_settings.debug_mode
	
	# Get EntityManager reference
	if has_node("/root/EntityManager"):
		_entity_manager = get_node("/root/EntityManager")
	
	# Initialize after engine is ready
	call_deferred("initialize")

func initialize() -> void:
	if _initialized or _initializing:
		return
	
	_initializing = true
	
	if _debug_mode:
		print("ProjectilePoolManager: Initializing projectile pools")
	
	# Load projectile scenes
	_preload_projectile_scenes()
	
	# Initialize pools
	_initialize_pools()
	
	_initialized = true
	_initializing = false
	
	if _debug_mode:
		_log_pool_stats()
	
	# Signal that all pools are initialized
	pools_initialized.emit()

# Preload projectile scenes
func _preload_projectile_scenes() -> void:
	_load_scene("laser", LASER_PROJECTILE_PATH)
	_load_scene("missile", MISSILE_PROJECTILE_PATH)
	_load_scene("enemy", ENEMY_PROJECTILE_PATH)

# Load a scene into the cache
func _load_scene(key: String, path: String) -> void:
	if ResourceLoader.exists(path):
		_scene_cache[key] = load(path)
	else:
		push_error("ProjectilePoolManager: Scene file not found: " + path)

# Initialize all projectile pools
func _initialize_pools() -> void:
	_initialize_pool("laser", laser_pool_size)
	_initialize_pool("missile", missile_pool_size)
	_initialize_pool("enemy", enemy_projectile_pool_size)

# Initialize a specific projectile pool
func _initialize_pool(pool_name: String, pool_size: int) -> void:
	if not _scene_cache.has(pool_name):
		push_error("ProjectilePoolManager: Cannot initialize pool - missing scene: " + pool_name)
		return
	
	var pool = []
	
	for i in range(pool_size):
		var projectile = _create_projectile(pool_name)
		if projectile:
			pool.append(projectile)
	
	_projectile_pools[pool_name] = pool

# Create a single projectile
func _create_projectile(projectile_type: String) -> Node:
	if not _scene_cache.has(projectile_type):
		return null
	
	var projectile = _scene_cache[projectile_type].instantiate()
	add_child(projectile)
	
	# Set initial state
	projectile.visible = false
	
	# Configure based on type
	if projectile.has_method("set_projectile_type"):
		projectile.set_projectile_type(projectile_type)
	
	# Add to projectiles group
	if not projectile.is_in_group("projectiles"):
		projectile.add_to_group("projectiles")
	
	return projectile

# Get a projectile from a specific pool
func get_projectile(projectile_type: String, position: Vector2, direction: Vector2, source_node = null) -> Node:
	if not _initialized:
		await initialize()
	
	# Make sure pool exists
	if not _projectile_pools.has(projectile_type):
		if _debug_mode:
			push_error("ProjectilePoolManager: Unknown projectile type: " + projectile_type)
		return null
	
	# Get from pool
	var projectile = _get_from_pool(projectile_type)
	if not projectile:
		return null
	
	# Configure projectile
	_configure_projectile(projectile, projectile_type, position, direction, source_node)
	
	# Track active projectile
	_active_projectiles.append(projectile)
	
	return projectile

# Get an inactive projectile from the pool
func _get_from_pool(pool_name: String) -> Node:
	var pool = _projectile_pools.get(pool_name, [])
	
	# First try to find an inactive projectile
	for projectile in pool:
		if is_instance_valid(projectile) and not projectile.visible:
			projectile.visible = true
			return projectile
	
	# If no projectiles available, create a new one if auto-expand is enabled
	if auto_expand_pools and _scene_cache.has(pool_name):
		if _debug_mode:
			print("ProjectilePoolManager: Expanding " + pool_name + " pool")
			
		var new_projectile = _create_projectile(pool_name)
		if new_projectile:
			pool.append(new_projectile)
			_projectile_pools[pool_name] = pool
			new_projectile.visible = true
			return new_projectile
	
	# If no projectiles available and auto-expand is disabled, return null
	if _debug_mode:
		print("ProjectilePoolManager: No " + pool_name + " projectiles available!")
		
	return null

# Configure a projectile for use
func _configure_projectile(projectile: Node, projectile_type: String, position: Vector2, direction: Vector2, source_node = null) -> void:
	# Set position
	projectile.global_position = position
	
	# Set direction and speed based on type
	if projectile.has_method("fire"):
		projectile.fire(direction, source_node)
	else:
		# Fallback configuration for basic projectiles
		if projectile is RigidBody2D:
			# Apply impulse in direction
			var speed = 500.0  # Default speed
			if projectile_type == "missile":
				speed = 300.0
			elif projectile_type == "enemy":
				speed = 400.0
				
			projectile.linear_velocity = direction * speed
		
		# Set rotation to match direction
		if "rotation" in projectile:
			projectile.rotation = direction.angle()
	
	# Register with EntityManager if available
	if _entity_manager and _entity_manager.has_method("register_entity"):
		_entity_manager.register_entity(projectile, "projectile")

# Return a projectile to the pool
func return_projectile(projectile: Node) -> void:
	if not is_instance_valid(projectile):
		return
	
	# Reset state
	projectile.visible = false
	
	if projectile is RigidBody2D:
		projectile.linear_velocity = Vector2.ZERO
		projectile.angular_velocity = 0.0
	
	# Deregister with EntityManager if available
	if _entity_manager and _entity_manager.has_method("deregister_entity"):
		_entity_manager.deregister_entity(projectile)
	
	# Remove from active projectiles list
	var index = _active_projectiles.find(projectile)
	if index >= 0:
		_active_projectiles.remove_at(index)

# Return all active projectiles to the pool
func clear_active_projectiles() -> void:
	var active_copy = _active_projectiles.duplicate()
	for projectile in active_copy:
		if is_instance_valid(projectile):
			return_projectile(projectile)

# Debug logging
func _log_pool_stats() -> void:
	if not _debug_mode:
		return
		
	print("ProjectilePoolManager: Projectile pool statistics:")
	for pool_name in _projectile_pools:
		var pool_size = _projectile_pools[pool_name].size()
		print("- " + pool_name + " projectiles: " + str(pool_size))
