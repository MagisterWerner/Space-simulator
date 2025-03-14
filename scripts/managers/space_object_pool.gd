# scripts/managers/space_object_pool.gd
extends Node
class_name SpaceObjectPool

signal pools_initialized

# Pool configuration
@export_group("Pool Configuration")
@export var debris_pool_size: int = 30
@export var collectible_pool_size: int = 20
@export var asteroid_mini_pool_size: int = 15
@export var space_dust_pool_size: int = 50
@export var auto_expand_pools: bool = true

# Object scene paths
const DEBRIS_SCENE_PATH = "res://scenes/objects/space_debris.tscn"
const COLLECTIBLE_SCENE_PATH = "res://scenes/objects/collectible.tscn"
const ASTEROID_MINI_SCENE_PATH = "res://scenes/objects/asteroid_mini.tscn"
const SPACE_DUST_SCENE_PATH = "res://scenes/objects/space_dust.tscn"

# Object pools
var _object_pools = {}
var _active_objects = []

# Initialization tracking
var _initialized: bool = false
var _initializing: bool = false

# Cache for object scenes
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
		print("SpaceObjectPool: Initializing object pools")
	
	# Load object scenes
	_preload_scenes()
	
	# Initialize pools
	_initialize_pools()
	
	_initialized = true
	_initializing = false
	
	if _debug_mode:
		_log_pool_stats()
	
	# Signal that all pools are initialized
	pools_initialized.emit()

# Preload object scenes
func _preload_scenes() -> void:
	_load_scene("debris", DEBRIS_SCENE_PATH)
	_load_scene("collectible", COLLECTIBLE_SCENE_PATH)
	_load_scene("asteroid_mini", ASTEROID_MINI_SCENE_PATH)
	_load_scene("space_dust", SPACE_DUST_SCENE_PATH)

# Load a scene into the cache
func _load_scene(key: String, path: String) -> void:
	if ResourceLoader.exists(path):
		_scene_cache[key] = load(path)
	else:
		_create_fallback_scene(key)

# Create fallback scene if original not found
func _create_fallback_scene(object_type: String) -> void:
	var scene = PackedScene.new()
	var root
	
	match object_type:
		"debris":
			root = RigidBody2D.new()
			root.name = "DebrisFallback"
			
			var sprite = Sprite2D.new()
			sprite.name = "Sprite"
			
			var img = Image.create(8, 8, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.6, 0.4, 0.2))
			sprite.texture = ImageTexture.create_from_image(img)
			
			root.add_child(sprite)
			
		"collectible":
			root = Area2D.new()
			root.name = "CollectibleFallback"
			
			var sprite = Sprite2D.new()
			sprite.name = "Sprite"
			
			var img = Image.create(12, 12, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.9, 0.9, 0.2))
			sprite.texture = ImageTexture.create_from_image(img)
			
			var collision = CollisionShape2D.new()
			collision.name = "CollisionShape"
			collision.shape = CircleShape2D.new()
			collision.shape.radius = 6
			
			root.add_child(sprite)
			root.add_child(collision)
			
		"asteroid_mini":
			root = RigidBody2D.new()
			root.name = "AsteroidMiniFallback"
			
			var sprite = Sprite2D.new()
			sprite.name = "Sprite"
			
			var img = Image.create(10, 10, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.6, 0.6, 0.6))
			sprite.texture = ImageTexture.create_from_image(img)
			
			var collision = CollisionShape2D.new()
			collision.name = "CollisionShape"
			collision.shape = CircleShape2D.new()
			collision.shape.radius = 5
			
			root.add_child(sprite)
			root.add_child(collision)
			
		"space_dust":
			root = CPUParticles2D.new()
			root.name = "SpaceDustFallback"
			root.amount = 1
			root.emitting = false
			root.one_shot = false
			root.lifetime = 1.0
			root.color = Color(0.8, 0.8, 0.8, 0.5)
			
		_:
			root = Node2D.new()
			root.name = "FallbackObject"
	
	scene.pack(root)
	_scene_cache[object_type] = scene
	
	if _debug_mode:
		print("SpaceObjectPool: Created fallback scene for " + object_type)

# Initialize all object pools
func _initialize_pools() -> void:
	_initialize_pool("debris", debris_pool_size)
	_initialize_pool("collectible", collectible_pool_size)
	_initialize_pool("asteroid_mini", asteroid_mini_pool_size)
	_initialize_pool("space_dust", space_dust_pool_size)

# Initialize a specific object pool
func _initialize_pool(pool_name: String, pool_size: int) -> void:
	if not _scene_cache.has(pool_name):
		push_error("SpaceObjectPool: Cannot initialize pool - missing scene: " + pool_name)
		return
	
	var pool = []
	
	for i in range(pool_size):
		var object = _create_object(pool_name)
		if object:
			pool.append(object)
	
	_object_pools[pool_name] = pool

# Create a single object
func _create_object(object_type: String) -> Node:
	if not _scene_cache.has(object_type):
		return null
	
	var object = _scene_cache[object_type].instantiate()
	add_child(object)
	
	# Set initial state
	object.visible = false
	
	# Configure based on type
	match object_type:
		"debris":
			if object is RigidBody2D:
				object.linear_velocity = Vector2.ZERO
				object.angular_velocity = 0.0
				object.sleeping = true
			
		"collectible":
			if object.has_method("set_collected"):
				object.set_collected(false)
			
		"asteroid_mini":
			if object is RigidBody2D:
				object.linear_velocity = Vector2.ZERO
				object.angular_velocity = 0.0
				object.sleeping = true
			
		"space_dust":
			if object is CPUParticles2D or object is GPUParticles2D:
				object.emitting = false
	
	# Add to group
	if not object.is_in_group("space_objects"):
		object.add_to_group("space_objects")
	
	# Add to specific group
	if not object.is_in_group(object_type + "_objects"):
		object.add_to_group(object_type + "_objects")
	
	return object

# Get an object from a specific pool
func get_object(object_type: String, position: Vector2, params: Dictionary = {}) -> Node:
	if not _initialized:
		await initialize()
	
	# Make sure pool exists
	if not _object_pools.has(object_type):
		if _debug_mode:
			push_error("SpaceObjectPool: Unknown object type: " + object_type)
		return null
	
	# Get from pool
	var object = _get_from_pool(object_type)
	if not object:
		return null
	
	# Configure object
	_configure_object(object, object_type, position, params)
	
	# Track active object
	_active_objects.append(object)
	
	return object

# Get an inactive object from the pool
func _get_from_pool(pool_name: String) -> Node:
	var pool = _object_pools.get(pool_name, [])
	
	# First try to find an inactive object
	for object in pool:
		if is_instance_valid(object) and not object.visible:
			object.visible = true
			return object
	
	# If no objects available, create a new one if auto-expand is enabled
	if auto_expand_pools and _scene_cache.has(pool_name):
		if _debug_mode:
			print("SpaceObjectPool: Expanding " + pool_name + " pool")
			
		var new_object = _create_object(pool_name)
		if new_object:
			pool.append(new_object)
			_object_pools[pool_name] = pool
			new_object.visible = true
			return new_object
	
	# If no objects available and auto-expand is disabled, return null
	if _debug_mode:
		print("SpaceObjectPool: No " + pool_name + " objects available!")
		
	return null

# Configure an object based on type and parameters
func _configure_object(object: Node, object_type: String, position: Vector2, params: Dictionary) -> void:
	# Set position
	object.global_position = position
	
	# Configure object based on type
	match object_type:
		"debris":
			_configure_debris(object, params)
			
		"collectible":
			_configure_collectible(object, params)
			
		"asteroid_mini":
			_configure_asteroid_mini(object, params)
			
		"space_dust":
			_configure_space_dust(object, params)
	
	# Register with EntityManager if available
	if _entity_manager and _entity_manager.has_method("register_entity"):
		_entity_manager.register_entity(object, object_type)
	
	# Setup auto-return after lifetime if specified
	if params.has("lifetime") and params.lifetime > 0:
		get_tree().create_timer(params.lifetime).timeout.connect(
			func(): return_object(object)
		)

# Configure debris object
func _configure_debris(debris: Node, params: Dictionary) -> void:
	# Set rotation if applicable
	if "rotation" in debris:
		debris.rotation = params.get("rotation", randf() * TAU)
	
	# Set scale if applicable
	if "scale" in debris:
		var scale_value = params.get("scale", randf_range(0.5, 1.5))
		debris.scale = Vector2(scale_value, scale_value)
	
	# Physics properties if rigid body
	if debris is RigidBody2D:
		# Apply velocity
		var velocity = params.get("velocity", Vector2.ZERO)
		if velocity == Vector2.ZERO:
			var speed = params.get("speed", randf_range(20.0, 50.0))
			var direction = params.get("direction", Vector2.from_angle(randf() * TAU))
			velocity = direction * speed
		
		debris.linear_velocity = velocity
		debris.angular_velocity = params.get("angular_velocity", randf_range(-3.0, 3.0))
		debris.sleeping = false
	
	# Set texture if specified and has sprite
	var sprite = debris.get_node_or_null("Sprite2D") if debris else null
	if sprite and params.has("texture"):
		sprite.texture = params.texture
	
	# Apply custom modulate if specified
	if params.has("modulate") and sprite:
		sprite.modulate = params.modulate

# Configure collectible object
func _configure_collectible(collectible: Node, params: Dictionary) -> void:
	# Set collectible type
	if collectible.has_method("set_type"):
		collectible.set_type(params.get("type", 0))
	
	# Set value
	if collectible.has_method("set_value"):
		collectible.set_value(params.get("value", 1))
	
	# Set texture if specified and has sprite
	var sprite = collectible.get_node_or_null("Sprite2D") if collectible else null
	if sprite and params.has("texture"):
		sprite.texture = params.texture
	
	# Apply custom modulate if specified
	if params.has("modulate") and sprite:
		sprite.modulate = params.modulate
	
	# Initialize animation if applicable
	if collectible.has_method("init_animation"):
		collectible.init_animation()

# Configure mini asteroid object
func _configure_asteroid_mini(asteroid: Node, params: Dictionary) -> void:
	# Set rotation if applicable
	if "rotation" in asteroid:
		asteroid.rotation = params.get("rotation", randf() * TAU)
	
	# Set scale if applicable
	if "scale" in asteroid:
		var scale_value = params.get("scale", randf_range(0.2, 0.5))
		asteroid.scale = Vector2(scale_value, scale_value)
	
	# Physics properties if rigid body
	if asteroid is RigidBody2D:
		# Apply velocity
		var velocity = params.get("velocity", Vector2.ZERO)
		if velocity == Vector2.ZERO:
			var speed = params.get("speed", randf_range(10.0, 30.0))
			var direction = params.get("direction", Vector2.from_angle(randf() * TAU))
			velocity = direction * speed
		
		asteroid.linear_velocity = velocity
		asteroid.angular_velocity = params.get("angular_velocity", randf_range(-2.0, 2.0))
		asteroid.gravity_scale = 0.0
		asteroid.sleeping = false
	
	# Set variant if applicable
	if asteroid.has_method("set_variant"):
		asteroid.set_variant(params.get("variant", 0))

# Configure space dust object
func _configure_space_dust(dust: Node, params: Dictionary) -> void:
	if dust is CPUParticles2D or dust is GPUParticles2D:
		# Set emitting
		dust.emitting = true
		
		# Set color if specified
		if params.has("color"):
			dust.color = params.color
		
		# Set amount if specified
		if params.has("amount"):
			dust.amount = params.amount
		
		# Set direction and spread if specified
		if params.has("direction"):
			dust.direction = params.direction
		
		if params.has("spread"):
			dust.spread = params.spread
		
		# Set lifetime if specified
		if params.has("particle_lifetime"):
			dust.lifetime = params.particle_lifetime

# Return an object to the pool
func return_object(object: Node) -> void:
	if not is_instance_valid(object):
		return
	
	# Reset state
	object.visible = false
	
	# Reset based on type
	if object.is_in_group("debris_objects") or object.is_in_group("asteroid_mini_objects"):
		if object is RigidBody2D:
			object.linear_velocity = Vector2.ZERO
			object.angular_velocity = 0.0
			object.sleeping = true
		
	elif object.is_in_group("collectible_objects"):
		if object.has_method("set_collected"):
			object.set_collected(false)
		
	elif object.is_in_group("space_dust_objects"):
		if object is CPUParticles2D or object is GPUParticles2D:
			object.emitting = false
	
	# Deregister with EntityManager if available
	if _entity_manager and _entity_manager.has_method("deregister_entity"):
		_entity_manager.deregister_entity(object)
	
	# Remove from active objects list
	var index = _active_objects.find(object)
	if index >= 0:
		_active_objects.remove_at(index)

# Return all active objects to the pool
func clear_active_objects() -> void:
	var active_copy = _active_objects.duplicate()
	for object in active_copy:
		if is_instance_valid(object):
			return_object(object)

# Convenience methods for common objects
func spawn_debris(position: Vector2, params: Dictionary = {}) -> Node:
	return get_object("debris", position, params)

func spawn_collectible(position: Vector2, params: Dictionary = {}) -> Node:
	return get_object("collectible", position, params)

func spawn_asteroid_mini(position: Vector2, params: Dictionary = {}) -> Node:
	return get_object("asteroid_mini", position, params)

func spawn_space_dust(position: Vector2, params: Dictionary = {}) -> Node:
	return get_object("space_dust", position, params)

# Debug logging
func _log_pool_stats() -> void:
	if not _debug_mode:
		return
		
	print("SpaceObjectPool: Object pool statistics:")
	for pool_name in _object_pools:
		var pool_size = _object_pools[pool_name].size()
		print("- " + pool_name + " objects: " + str(pool_size))
