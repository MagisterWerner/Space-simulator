extends EntitySpawner
class_name FragmentSpawner

# Fragment-specific configuration
@export_category("Fragment Configuration")
@export var asteroid_fragment_scene_path: String = "res://scenes/entities/asteroid.tscn"
@export var debris_fragment_scene_path: String = "res://scenes/effects/debris_fragment.tscn"
@export var asteroid_generator_path: String = "res://scripts/generators/asteroid_generator.gd"

# Fragment Properties
@export_category("Fragment Properties")
@export var default_fragment_lifetime: float = 10.0
@export var max_fragments_per_pattern: int = 5
@export var max_concurrent_patterns: int = 3

# Pattern Management
@export_category("Pattern Management")
@export var use_pattern_pooling: bool = true
@export var pattern_cleanup_interval: float = 5.0

# Debug Options
@export var debug_fragments: bool = false

# Scene caches
var _asteroid_fragment_scene = null
var _debris_fragment_scene = null
var _asteroid_generator = null
var _asteroid_generator_instance = null

# Pattern tracking
var _active_patterns: Dictionary = {}  # Maps pattern_id to array of fragments
var _pattern_timers: Dictionary = {}    # Maps pattern_id to lifetime timer
var _next_pattern_id: int = 1
var _cleanup_timer: float = 0.0

# Texture caching for performance
var _texture_cache: Dictionary = {}
const MAX_TEXTURE_CACHE_SIZE: int = 20

func _ready() -> void:
	# Set entity type for fragments
	entity_type = "fragment"
	
	# Load scenes
	_load_fragment_scenes()
	
	# Initialize asteroid generator
	_initialize_asteroid_generator()

func _load_fragment_scenes() -> void:
	# Load asteroid fragment scene
	if ResourceLoader.exists(asteroid_fragment_scene_path):
		_asteroid_fragment_scene = load(asteroid_fragment_scene_path)
	else:
		push_error("FragmentSpawner: Asteroid fragment scene not found: " + asteroid_fragment_scene_path)
	
	# Load debris fragment scene
	if ResourceLoader.exists(debris_fragment_scene_path):
		_debris_fragment_scene = load(debris_fragment_scene_path)
	else:
		# Not a critical error if debris scene isn't available
		if debug_fragments:
			print("FragmentSpawner: Debris fragment scene not found, will use asteroid fragments only")
	
	if debug_fragments:
		print("FragmentSpawner: Fragment scenes loaded")

func _initialize_asteroid_generator() -> void:
	if ResourceLoader.exists(asteroid_generator_path):
		_asteroid_generator = load(asteroid_generator_path)
		
		# Create generator instance
		_asteroid_generator_instance = _asteroid_generator.new()
		add_child(_asteroid_generator_instance)
		
		if debug_fragments:
			print("FragmentSpawner: Asteroid generator initialized")
	else:
		push_error("FragmentSpawner: Failed to load asteroid generator: " + asteroid_generator_path)

func _process(delta: float) -> void:
	_cleanup_timer += delta
	
	# Do periodic cleanup of expired patterns
	if _cleanup_timer >= pattern_cleanup_interval:
		_cleanup_timer = 0.0
		_cleanup_expired_patterns()
	
	# Update pattern lifetimes
	_update_pattern_timers(delta)

# Spawn a fragment pattern based on the data
func spawn_pattern(pattern_data: FragmentPatternData) -> int:
	if _active_patterns.size() >= max_concurrent_patterns and not use_pattern_pooling:
		# Find the oldest pattern and remove it
		var oldest_pattern_id = -1
		var oldest_time = INF
		
		for pattern_id in _pattern_timers:
			if _pattern_timers[pattern_id] < oldest_time:
				oldest_time = _pattern_timers[pattern_id]
				oldest_pattern_id = pattern_id
		
		if oldest_pattern_id > 0:
			despawn_pattern(oldest_pattern_id)
	
	# Create a unique pattern ID
	var pattern_id = _next_pattern_id
	_next_pattern_id += 1
	
	# Initialize pattern tracking
	_active_patterns[pattern_id] = []
	_pattern_timers[pattern_id] = default_fragment_lifetime
	
	# Limit fragments to maximum
	var fragment_count = min(pattern_data.fragments.size(), max_fragments_per_pattern)
	
	# Spawn each fragment in the pattern
	for i in range(fragment_count):
		var fragment = pattern_data.fragments[i]
		
		# Determine if this is an asteroid fragment or debris
		var is_asteroid = true
		if fragment.has("is_debris") and fragment.is_debris:
			is_asteroid = false
		
		# Spawn the appropriate fragment type
		var fragment_instance = null
		if is_asteroid:
			fragment_instance = _spawn_asteroid_fragment(pattern_data, fragment, i)
		else:
			fragment_instance = _spawn_debris_fragment(pattern_data, fragment, i)
		
		# Track the fragment with this pattern
		if fragment_instance:
			_active_patterns[pattern_id].append(fragment_instance)
	
	if debug_fragments:
		print("FragmentSpawner: Spawned pattern ", pattern_id, " with ", _active_patterns[pattern_id].size(), " fragments")
	
	return pattern_id

# Spawn an asteroid fragment
func _spawn_asteroid_fragment(pattern_data: FragmentPatternData, fragment: Dictionary, index: int) -> Node:
	if not _asteroid_fragment_scene:
		return null
	
	# Generate a unique entity ID for this fragment
	var entity_id = pattern_data.source_entity_id * 1000 + index
	
	# Check if we already have this fragment (shouldn't happen)
	if _entity_map.has(entity_id):
		return _entity_map[entity_id]
	
	# Instance the asteroid
	var asteroid = _asteroid_fragment_scene.instantiate()
	add_child(asteroid)
	
	# Position the asteroid
	asteroid.global_position = pattern_data.source_position + fragment.position_offset
	
	# Configure the asteroid fragment
	_configure_asteroid_fragment(asteroid, pattern_data, fragment, entity_id)
	
	# Track the fragment
	_entity_map[entity_id] = asteroid
	
	# Register with EntityManager if enabled
	if auto_register_with_entity_manager and _entity_manager and _entity_manager.has_method("register_entity"):
		_entity_manager.register_entity(asteroid, "asteroid")
	
	# Connect to signals
	if not asteroid.tree_exiting.is_connected(_on_entity_tree_exiting):
		asteroid.tree_exiting.connect(_on_entity_tree_exiting.bind(asteroid))
	
	return asteroid

# Configure an asteroid fragment
func _configure_asteroid_fragment(asteroid: Node, pattern_data: FragmentPatternData, fragment: Dictionary, entity_id: int) -> void:
	# Generate a unique seed for this fragment
	var fragment_seed = pattern_data.pattern_seed + entity_id
	
	# Generate texture if we have a generator
	var texture = _get_asteroid_texture(fragment_seed)
	
	# Set sprite texture if available
	if texture and asteroid.has_node("Sprite2D"):
		asteroid.get_node("Sprite2D").texture = texture
	
	# Get fragment properties
	var size_category = fragment.get("size_category", "small")
	var size_factor = fragment.get("size_factor", 0.6)
	var velocity = fragment.get("velocity", Vector2.ZERO)
	var angular_velocity = fragment.get("angular_velocity", randf_range(-1.5, 1.5))
	
	# Apply inherited velocity if needed
	if velocity == Vector2.ZERO:
		var angle = randf() * TAU
		velocity = pattern_data.source_velocity + Vector2(cos(angle), sin(angle)) * 50.0
	
	# Set asteroid properties
	if "size_category" in asteroid:
		asteroid.size_category = size_category
	
	# Call setup method if available
	if asteroid.has_method("setup"):
		asteroid.setup(
			size_category,
			entity_id % 4,  # Variant
			size_factor,
			angular_velocity,
			velocity
		)
	
	# Set velocity directly if not handled by setup
	if not asteroid.has_method("setup") and asteroid is RigidBody2D:
		asteroid.linear_velocity = velocity
		asteroid.angular_velocity = angular_velocity

# Spawn a debris fragment
func _spawn_debris_fragment(pattern_data: FragmentPatternData, fragment: Dictionary, index: int) -> Node:
	if not _debris_fragment_scene:
		return null
	
	# Generate a unique entity ID for this fragment
	var entity_id = pattern_data.source_entity_id * 1000 + 500 + index
	
	# Instance the debris
	var debris = _debris_fragment_scene.instantiate()
	add_child(debris)
	
	# Position the debris
	debris.global_position = pattern_data.source_position + fragment.position_offset
	
	# Configure the debris fragment
	_configure_debris_fragment(debris, pattern_data, fragment, entity_id)
	
	# Track the fragment
	_entity_map[entity_id] = debris
	
	# Connect to signals
	if not debris.tree_exiting.is_connected(_on_entity_tree_exiting):
		debris.tree_exiting.connect(_on_entity_tree_exiting.bind(debris))
	
	return debris

# Configure a debris fragment
func _configure_debris_fragment(debris: Node, pattern_data: FragmentPatternData, fragment: Dictionary, entity_id: int) -> void:
	# Get fragment properties
	var velocity = fragment.get("velocity", Vector2.ZERO)
	var angular_velocity = fragment.get("angular_velocity", randf_range(-3.0, 3.0))
	var lifetime = fragment.get("lifetime", default_fragment_lifetime)
	
	# Apply inherited velocity if needed
	if velocity == Vector2.ZERO:
		var angle = randf() * TAU
		velocity = pattern_data.source_velocity + Vector2(cos(angle), sin(angle)) * 70.0
	
	# Set debris properties
	if "lifetime" in debris:
		debris.lifetime = lifetime
	
	# Apply velocity
	if debris is RigidBody2D:
		debris.linear_velocity = velocity
		debris.angular_velocity = angular_velocity
	
	# Connect signal for automatic cleanup
	if debris.has_signal("debris_expired") and not debris.is_connected("debris_expired", _on_debris_expired):
		debris.connect("debris_expired", _on_debris_expired.bind(debris))

# Handle debris expiry
func _on_debris_expired(debris: Node) -> void:
	despawn_entity_by_reference(debris)

# Get or generate asteroid texture
func _get_asteroid_texture(seed_value: int) -> Texture2D:
	if not _asteroid_generator_instance:
		return null
	
	# Try to get from cache first
	var cache_key = str(seed_value)
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]
	
	# Set the seed for the generator
	_asteroid_generator_instance.seed_value = seed_value
	
	# Generate new texture
	var texture = _asteroid_generator_instance.create_asteroid_texture()
	
	# Cache the texture
	if _texture_cache.size() >= MAX_TEXTURE_CACHE_SIZE:
		var first_key = _texture_cache.keys()[0]
		_texture_cache.erase(first_key)
	
	_texture_cache[cache_key] = texture
	return texture

# Despawn a specific pattern and all its fragments
func despawn_pattern(pattern_id: int) -> void:
	if not _active_patterns.has(pattern_id):
		return
	
	var fragments = _active_patterns[pattern_id].duplicate()
	
	# Despawn all fragments in this pattern
	for fragment in fragments:
		if is_instance_valid(fragment):
			despawn_entity_by_reference(fragment)
	
	# Remove pattern tracking
	_active_patterns.erase(pattern_id)
	_pattern_timers.erase(pattern_id)
	
	if debug_fragments:
		print("FragmentSpawner: Despawned pattern ", pattern_id)

# Update pattern lifetimes
func _update_pattern_timers(delta: float) -> void:
	for pattern_id in _pattern_timers.keys():
		_pattern_timers[pattern_id] -= delta
		
		# Check if pattern has expired
		if _pattern_timers[pattern_id] <= 0:
			despawn_pattern(pattern_id)

# Clean up expired or empty patterns
func _cleanup_expired_patterns() -> void:
	var patterns_to_remove = []
	
	for pattern_id in _active_patterns.keys():
		# Check if pattern has no fragments
		if _active_patterns[pattern_id].is_empty():
			patterns_to_remove.append(pattern_id)
			continue
		
		# Check if any fragments are invalid
		var valid_fragments = []
		for fragment in _active_patterns[pattern_id]:
			if is_instance_valid(fragment):
				valid_fragments.append(fragment)
		
		# Update the pattern with only valid fragments
		_active_patterns[pattern_id] = valid_fragments
		
		# If no valid fragments remain, mark for removal
		if valid_fragments.is_empty():
			patterns_to_remove.append(pattern_id)
	
	# Remove expired patterns
	for pattern_id in patterns_to_remove:
		_active_patterns.erase(pattern_id)
		_pattern_timers.erase(pattern_id)
	
	if debug_fragments and not patterns_to_remove.is_empty():
		print("FragmentSpawner: Cleaned up ", patterns_to_remove.size(), " expired patterns")

# Create and spawn a pattern from an explosion or destruction
func create_explosion_pattern(position: Vector2, source_id: int, size: String = "medium", velocity: Vector2 = Vector2.ZERO) -> int:
	# Create a pattern for the fragments
	var pattern = FragmentPatternData.new()
	pattern.pattern_seed = source_id + int(Time.get_unix_time_from_system()) % 100000
	pattern.source_entity_id = source_id
	pattern.source_position = position
	pattern.source_velocity = velocity
	pattern.source_size_category = size
	
	# Determine fragment count based on size
	var fragment_count = 0
	var fragment_type = ""
	
	if size == "small":
		fragment_count = 3  # Small debris only
		fragment_type = "debris"
	elif size == "medium":
		fragment_count = 5  # Mix of small asteroids and debris
		fragment_type = "mixed"
	elif size == "large":
		fragment_count = 7  # More fragments for large objects
		fragment_type = "mixed"
	
	# Generate a circular pattern
	pattern.generate_circular_pattern(fragment_count, 5.0, 30.0)
	
	# Add debris flags to some fragments
	for i in range(pattern.fragments.size()):
		var fragment = pattern.fragments[i]
		
		# For mixed type, make some fragments debris
		if fragment_type == "mixed":
			fragment["is_debris"] = (i % 2 == 0)
		# For debris type, make all fragments debris
		elif fragment_type == "debris":
			fragment["is_debris"] = true
		# For asteroid type, none are debris
		else:
			fragment["is_debris"] = false
		
		# Set lifetime for debris
		if fragment["is_debris"]:
			fragment["lifetime"] = randf_range(2.0, 5.0)
	
	# Spawn the pattern
	return spawn_pattern(pattern)

# Create fragments when an asteroid breaks apart
func create_asteroid_fragments(position: Vector2, size_category: String, parent_id: int, parent_velocity: Vector2 = Vector2.ZERO) -> int:
	if size_category == "small":
		return -1  # No fragments for small asteroids
	
	# Create a pattern for the fragments
	var pattern = FragmentPatternData.new()
	pattern.pattern_seed = parent_id + int(Time.get_unix_time_from_system()) % 100000
	pattern.source_entity_id = parent_id
	pattern.source_position = position
	pattern.source_velocity = parent_velocity
	pattern.source_size_category = size_category
	
	var fragment_count = 0
	var fragment_type = ""
	
	if size_category == "large":
		fragment_count = 2  # 1 medium, 1 small
		fragment_type = "large"
	elif size_category == "medium":
		fragment_count = 2  # 2 small
		fragment_type = "medium"
	
	# Generate a circular pattern
	pattern.generate_circular_pattern(fragment_count, 10.0, 30.0)
	
	# Configure fragment types
	if fragment_type == "large":
		# First fragment is medium
		pattern.fragments[0]["size_category"] = "medium"
		pattern.fragments[0]["size_factor"] = 0.7
		
		# Second fragment is small
		pattern.fragments[1]["size_category"] = "small"
		pattern.fragments[1]["size_factor"] = 0.5
	else:
		# Both fragments are small
		for i in range(pattern.fragments.size()):
			pattern.fragments[i]["size_category"] = "small"
			pattern.fragments[i]["size_factor"] = 0.6
	
	# Spawn the pattern
	return spawn_pattern(pattern)

# Cleanup all patterns and fragments
func cleanup() -> void:
	# Despawn all patterns
	for pattern_id in _active_patterns.keys():
		despawn_pattern(pattern_id)
	
	# Clear tracking structures
	_active_patterns.clear()
	_pattern_timers.clear()
	
	# Clear texture cache
	_texture_cache.clear()
	
	super.cleanup()
