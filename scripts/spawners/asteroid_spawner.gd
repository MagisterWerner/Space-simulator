extends EntitySpawner
class_name AsteroidSpawnerNew

# Asteroid-specific configuration
@export_category("Asteroid Configuration")
@export var asteroid_scene_path: String = "res://scenes/entities/asteroid.tscn"
@export var asteroid_field_scene_path: String = "res://scenes/world/asteroid_field.tscn"
@export var asteroid_generator_path: String = "res://scripts/generators/asteroid_generator.gd"
@export var max_asteroids_per_field: int = 50
@export var pool_fields: bool = true
@export var pool_individual_asteroids: bool = true

# Debug Options
@export var debug_asteroid_generation: bool = false
@export var debug_asteroid_collisions: bool = false

# Scene caches
var _asteroid_scene = null
var _field_scene = null
var _asteroid_generator = null
var _asteroid_generator_instance = null

# Field tracking
var _asteroid_field_map: Dictionary = {}  # Maps field_id to field
var _field_asteroids: Dictionary = {}     # Maps field_id to array of asteroids
var _individual_asteroids: Array = []     # Standalone asteroids not part of a field

# Texture caching for performance
var _texture_cache: Dictionary = {}
const MAX_TEXTURE_CACHE_SIZE: int = 20

func _ready() -> void:
	# Set entity type for individual asteroids
	entity_type = "asteroid"
	
	# Load the entity scenes
	_load_asteroid_scenes()
	
	# Initialize asteroid generator
	_initialize_asteroid_generator()
	
	# Add to asteroid_fields group for world generator compatibility
	if not is_in_group("asteroid_fields"):
		add_to_group("asteroid_fields")

func _load_asteroid_scenes() -> void:
	# Load asteroid scene
	if ResourceLoader.exists(asteroid_scene_path):
		_asteroid_scene = load(asteroid_scene_path)
	else:
		push_error("AsteroidSpawner: Asteroid scene not found: " + asteroid_scene_path)
	
	# Load asteroid field scene
	if ResourceLoader.exists(asteroid_field_scene_path):
		_field_scene = load(asteroid_field_scene_path)
	else:
		push_error("AsteroidSpawner: Asteroid field scene not found: " + asteroid_field_scene_path)
	
	if debug_asteroid_generation:
		print("AsteroidSpawner: Scenes loaded")

func _initialize_asteroid_generator() -> void:
	if ResourceLoader.exists(asteroid_generator_path):
		_asteroid_generator = load(asteroid_generator_path)
		
		# Create generator instance
		_asteroid_generator_instance = _asteroid_generator.new()
		add_child(_asteroid_generator_instance)
		
		if debug_asteroid_generation:
			print("AsteroidSpawner: Asteroid generator initialized")
	else:
		push_error("AsteroidSpawner: Failed to load asteroid generator: " + asteroid_generator_path)

# Override validation to handle both asteroids and fields
func _validate_entity_data(entity_data) -> bool:
	if not super._validate_entity_data(entity_data):
		return false
	
	# Check for appropriate data types
	if entity_data is AsteroidData or entity_data is AsteroidFieldData:
		return true
	
	push_error("AsteroidSpawner: Invalid entity data, expected AsteroidData or AsteroidFieldData")
	return false

# Override spawn_entity to handle asteroid-specific logic
func spawn_entity(entity_data) -> Node:
	if not _validate_entity_data(entity_data):
		return null
	
	# Handle different entity types
	if entity_data is AsteroidFieldData:
		return _spawn_asteroid_field(entity_data)
	elif entity_data is AsteroidData:
		return _spawn_asteroid(entity_data)
	
	return null

# Spawn an asteroid field
func _spawn_asteroid_field(field_data: AsteroidFieldData) -> Node:
	var entity_id = field_data.entity_id
	
	# Check if we already have this field
	if _asteroid_field_map.has(entity_id):
		return _asteroid_field_map[entity_id]
	
	# Get the scene
	if not _field_scene:
		push_error("AsteroidSpawner: Cannot spawn asteroid field, scene not loaded")
		return null
	
	# Instance the field
	var field = _field_scene.instantiate()
	add_child(field)
	
	# Position the field
	field.global_position = field_data.world_position
	
	# Configure the field
	_configure_asteroid_field(field, field_data)
	
	# Track the field
	_asteroid_field_map[entity_id] = field
	_entity_map[entity_id] = field
	_data_map[entity_id] = field_data
	_field_asteroids[entity_id] = []
	
	# Register with EntityManager
	if auto_register_with_entity_manager and _entity_manager and _entity_manager.has_method("register_entity"):
		_entity_manager.register_entity(field, "asteroid_field")
	
	# Connect to signals
	if not field.tree_exiting.is_connected(_on_entity_tree_exiting):
		field.tree_exiting.connect(_on_entity_tree_exiting.bind(field))
	
	# Spawn asteroids for the field
	_spawn_field_asteroids(field, field_data)
	
	# Emit signal
	entity_spawned.emit(field, field_data)
	
	return field

# Configure an asteroid field with its data
func _configure_asteroid_field(field: Node, field_data: AsteroidFieldData) -> void:
	# Set grid position if applicable
	if field.has_method("set_grid_position"):
		field.set_grid_position(field_data.grid_cell.x, field_data.grid_cell.y)
	
	# Set field properties
	if "field_radius" in field:
		field.field_radius = field_data.field_radius
	if "min_asteroids" in field:
		field.min_asteroids = field_data.min_asteroids
	if "max_asteroids" in field:
		field.max_asteroids = field_data.max_asteroids
	if "min_distance_between" in field:
		field.min_distance_between = field_data.min_distance_between
	if "size_variation" in field:
		field.size_variation = field_data.size_variation
		
	# Size distribution
	if "small_asteroid_chance" in field:
		field.small_asteroid_chance = field_data.small_asteroid_chance
	if "medium_asteroid_chance" in field:
		field.medium_asteroid_chance = field_data.medium_asteroid_chance
	if "large_asteroid_chance" in field:
		field.large_asteroid_chance = field_data.large_asteroid_chance
		
	# Physics properties
	if "min_linear_speed" in field:
		field.min_linear_speed = field_data.min_linear_speed
	if "max_linear_speed" in field:
		field.max_linear_speed = field_data.max_linear_speed
	if "max_rotation_speed" in field:
		field.max_rotation_speed = field_data.max_rotation_speed
		
	# Debug settings
	if "debug_mode" in field:
		field.debug_mode = debug_asteroid_generation
	if "debug_asteroid_collisions" in field:
		field.debug_asteroid_collisions = debug_asteroid_collisions
	
	# Local seed offset from parent field
	if "local_seed_offset" in field:
		field.local_seed_offset = field_data.seed_value

# Spawn asteroids for a field
func _spawn_field_asteroids(field: Node, field_data: AsteroidFieldData) -> void:
	# If the field has its own generation capability, use that
	if field.has_method("generate_field"):
		field.generate_field()
		return
	
	# Otherwise, generate asteroids manually
	var asteroid_count = min(field_data.asteroid_count, max_asteroids_per_field)
	var field_id = field_data.entity_id
	
	# Use deterministic RNG for asteroid placement
	var rng = RandomNumberGenerator.new()
	rng.seed = field_data.seed_value
	
	for i in range(asteroid_count):
		# Generate asteroid data
		var asteroid_data = _generate_asteroid_data(field_data, i, rng)
		
		# Spawn the asteroid
		var asteroid = _spawn_asteroid(asteroid_data)
		
		# Track it with the field
		if asteroid:
			_field_asteroids[field_id].append(asteroid)

# Generate asteroid data for a field
func _generate_asteroid_data(field_data: AsteroidFieldData, index: int, rng: RandomNumberGenerator) -> AsteroidData:
	var asteroid_data = AsteroidData.new()
	asteroid_data.entity_id = field_data.entity_id * 1000 + index
	asteroid_data.seed_value = field_data.seed_value + index
	asteroid_data.grid_cell = field_data.grid_cell
	
	# Determine asteroid position within field
	var angle = rng.randf() * TAU
	var distance = rng.randf() * field_data.field_radius
	var offset = Vector2(cos(angle), sin(angle)) * distance
	asteroid_data.world_position = field_data.world_position + offset
	
	# Determine size category
	var size_roll = rng.randf()
	if size_roll < field_data.small_asteroid_chance:
		asteroid_data.size_category = "small"
	elif size_roll < field_data.small_asteroid_chance + field_data.medium_asteroid_chance:
		asteroid_data.size_category = "medium"
	else:
		asteroid_data.size_category = "large"
	
	# Apply size from string to set other properties
	asteroid_data.set_size_from_string(asteroid_data.size_category)
	
	# Generate physics properties
	var speed = rng.randf_range(field_data.min_linear_speed, field_data.max_linear_speed)
	var vel_angle = rng.randf() * TAU
	asteroid_data.velocity = Vector2(cos(vel_angle), sin(vel_angle)) * speed
	asteroid_data.angular_velocity = rng.randf_range(-field_data.max_rotation_speed, field_data.max_rotation_speed)
	
	# Set reference to parent field
	asteroid_data.field_id = field_data.entity_id
	
	return asteroid_data

# Spawn a single asteroid
func _spawn_asteroid(asteroid_data: AsteroidData) -> Node:
	var entity_id = asteroid_data.entity_id
	
	# Check if we already have this asteroid
	if _entity_map.has(entity_id):
		return _entity_map[entity_id]
	
	# Get the asteroid scene
	if not _asteroid_scene:
		push_error("AsteroidSpawner: Cannot spawn asteroid, scene not loaded")
		return null
	
	# Instance the asteroid
	var asteroid = _asteroid_scene.instantiate()
	add_child(asteroid)
	
	# Position the asteroid
	asteroid.global_position = asteroid_data.world_position
	
	# Configure the asteroid
	_configure_asteroid(asteroid, asteroid_data)
	
	# Track the asteroid
	_entity_map[entity_id] = asteroid
	_data_map[entity_id] = asteroid_data
	
	# Add to tracking lists
	if asteroid_data.field_id > 0 and _field_asteroids.has(asteroid_data.field_id):
		_field_asteroids[asteroid_data.field_id].append(asteroid)
	else:
		_individual_asteroids.append(asteroid)
	
	# Register with EntityManager
	if auto_register_with_entity_manager and _entity_manager and _entity_manager.has_method("register_entity"):
		_entity_manager.register_entity(asteroid, "asteroid")
	
	# Connect to signals
	if not asteroid.tree_exiting.is_connected(_on_entity_tree_exiting):
		asteroid.tree_exiting.connect(_on_entity_tree_exiting.bind(asteroid))
	
	# Connect to asteroid_destroyed signal if it exists
	if asteroid.has_signal("asteroid_destroyed") and not asteroid.is_connected("asteroid_destroyed", _on_asteroid_destroyed):
		asteroid.connect("asteroid_destroyed", _on_asteroid_destroyed)
	
	# Emit signal
	entity_spawned.emit(asteroid, asteroid_data)
	
	return asteroid

# Configure an asteroid with its data
func _configure_asteroid(asteroid: Node, asteroid_data: AsteroidData) -> void:
	# Generate texture if we have a generator
	var texture = _get_asteroid_texture(asteroid_data)
	
	# Set sprite texture if available
	if texture and asteroid.has_node("Sprite2D"):
		asteroid.get_node("Sprite2D").texture = texture
	
	# Set asteroid properties
	if "size_category" in asteroid:
		asteroid.size_category = asteroid_data.size_category
	if "points_value" in asteroid:
		asteroid.points_value = asteroid_data.points_value
	
	# Set debug properties
	if "debug_collision_shapes" in asteroid:
		asteroid.debug_collision_shapes = debug_asteroid_collisions
	
	# Call setup method if available
	if asteroid.has_method("setup"):
		asteroid.setup(
			asteroid_data.size_category,
			asteroid_data.variant,
			asteroid_data.entity_scale,
			asteroid_data.angular_velocity,
			asteroid_data.velocity
		)
	
	# Set velocity directly if not handled by setup
	if not asteroid.has_method("setup") and asteroid is RigidBody2D:
		asteroid.linear_velocity = asteroid_data.velocity
		asteroid.angular_velocity = asteroid_data.angular_velocity

# Get or generate asteroid texture
func _get_asteroid_texture(asteroid_data: AsteroidData) -> Texture2D:
	if not _asteroid_generator_instance:
		return null
	
	# Try to get from cache first
	var cache_key = str(asteroid_data.seed_value)
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]
	
	# Set the seed for the generator
	_asteroid_generator_instance.seed_value = asteroid_data.seed_value
	
	# Generate new texture
	var texture = _asteroid_generator_instance.create_asteroid_texture()
	
	# Cache the texture
	if _texture_cache.size() >= MAX_TEXTURE_CACHE_SIZE:
		var first_key = _texture_cache.keys()[0]
		_texture_cache.erase(first_key)
	
	_texture_cache[cache_key] = texture
	return texture

# Handle asteroid destruction event
func _on_asteroid_destroyed(position: Vector2, size: String, points: int) -> void:
	# Find the asteroid that was destroyed
	var asteroid = null
	var asteroid_data = null
	var entity_id = -1
	
	for id in _entity_map:
		var entity = _entity_map[id]
		if is_instance_valid(entity) and entity.global_position.is_equal_approx(position):
			asteroid = entity
			asteroid_data = _data_map[id]
			entity_id = id
			break
	
	if not asteroid or not asteroid_data:
		return
	
	# Create fragments if needed
	if size != "small" and asteroid_data is AsteroidData:
		_spawn_asteroid_fragments(position, size, asteroid_data)
	
	# Remove from tracking
	_entity_map.erase(entity_id)
	_data_map.erase(entity_id)
	
	# Remove from field tracking
	if asteroid_data.field_id > 0 and _field_asteroids.has(asteroid_data.field_id):
		var field_asteroids = _field_asteroids[asteroid_data.field_id]
		var index = field_asteroids.find(asteroid)
		if index >= 0:
			field_asteroids.remove_at(index)
	else:
		var index = _individual_asteroids.find(asteroid)
		if index >= 0:
			_individual_asteroids.remove_at(index)

# Spawn asteroid fragments when an asteroid is destroyed
func _spawn_asteroid_fragments(position: Vector2, size_category: String, parent_data: AsteroidData) -> void:
	if size_category == "small":
		return
	
	var fragment_count = 0
	var fragment_type = ""
	
	if size_category == "large":
		fragment_count = 2
		fragment_type = "medium"
	elif size_category == "medium":
		fragment_count = 2
		fragment_type = "small"
	
	# Create a pattern for the fragments
	var pattern = FragmentPatternData.new()
	pattern.pattern_seed = parent_data.seed_value
	pattern.source_entity_id = parent_data.entity_id
	pattern.source_position = position
	pattern.source_velocity = parent_data.velocity
	pattern.source_size_category = size_category
	
	# Generate a circular pattern
	pattern.generate_circular_pattern(fragment_count, 10.0, 30.0)
	
	# Create fragment data and spawn them
	for i in range(fragment_count):
		if i >= pattern.fragments.size():
			break
			
		var fragment = pattern.fragments[i]
		
		var asteroid_data = AsteroidData.new()
		asteroid_data.entity_id = parent_data.entity_id * 10 + i + 1
		asteroid_data.seed_value = parent_data.seed_value + 1000 + i
		asteroid_data.grid_cell = parent_data.grid_cell
		asteroid_data.world_position = position + fragment.position_offset
		asteroid_data.size_category = fragment.size_category if fragment.size_category else fragment_type
		asteroid_data.set_size_from_string(asteroid_data.size_category)
		asteroid_data.entity_scale = fragment.size_factor
		asteroid_data.velocity = fragment.velocity
		asteroid_data.angular_velocity = randf_range(-1.5, 1.5)
		asteroid_data.parent_asteroid_id = parent_data.entity_id
		
		# Spawn the fragment
		_spawn_asteroid(asteroid_data)

# Clear asteroid texture cache
func clear_texture_cache() -> void:
	_texture_cache.clear()
	
	if debug_asteroid_generation:
		print("AsteroidSpawner: Texture cache cleared")

# Override despawn to handle fields and their asteroids
func despawn_entity(entity_id: int) -> void:
	if not _entity_map.has(entity_id):
		return
	
	var entity = _entity_map[entity_id]
	var entity_data = _data_map[entity_id]
	
	# Handle asteroid field case
	if entity_data is AsteroidFieldData:
		# Despawn all asteroids in this field
		if _field_asteroids.has(entity_id):
			var asteroids = _field_asteroids[entity_id].duplicate()
			for asteroid in asteroids:
				if is_instance_valid(asteroid):
					# Find the asteroid entity ID
					var asteroid_id = -1
					for id in _entity_map:
						if _entity_map[id] == asteroid:
							asteroid_id = id
							break
					
					if asteroid_id > 0:
						despawn_entity(asteroid_id)
			
			_field_asteroids.erase(entity_id)
		
		# Remove from field map
		_asteroid_field_map.erase(entity_id)
	
	# Handle individual asteroid case
	elif entity_data is AsteroidData:
		var index = _individual_asteroids.find(entity)
		if index >= 0:
			_individual_asteroids.remove_at(index)
	
	# Deregister with EntityManager
	if auto_register_with_entity_manager and _entity_manager and _entity_manager.has_method("deregister_entity"):
		_entity_manager.deregister_entity(entity)
	
	# Emit signal
	entity_despawned.emit(entity, entity_data)
	
	# Remove from tracking
	_entity_map.erase(entity_id)
	_data_map.erase(entity_id)
	
	# Return to pool or free
	_return_entity_to_pool(entity)

# Legacy method for compatibility with existing asteroid field implementation
func handle_legacy_fragment_spawn(position: Vector2, size_category: String, count: int, parent_scale: float, parent_velocity: Vector2 = Vector2.ZERO) -> void:
	# Create a fake parent asteroid data
	var parent_data = AsteroidData.new()
	parent_data.entity_id = int(Time.get_unix_time_from_system()) % 10000
	parent_data.seed_value = parent_data.entity_id
	parent_data.world_position = position
	parent_data.size_category = size_category
	parent_data.entity_scale = parent_scale
	parent_data.velocity = parent_velocity
	
	# Spawn fragments using new system
	_spawn_asteroid_fragments(position, size_category, parent_data)

# Cleanup everything
func cleanup() -> void:
	super.cleanup()
	
	# Clear all tracking structures
	_asteroid_field_map.clear()
	_field_asteroids.clear()
	_individual_asteroids.clear()
	
	# Clear texture cache
	clear_texture_cache()
