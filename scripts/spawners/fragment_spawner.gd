extends EntitySpawnerBase
class_name FragmentSpawner

# Pool configuration
@export var small_fragment_pool_size: int = 20
@export var medium_fragment_pool_size: int = 15
@export var large_fragment_pool_size: int = 10
@export var patterns_per_size: int = 5
@export var auto_expand_pools: bool = true

# Explosion parameters
const EXPLOSION_FORCE_MIN = 40.0
const EXPLOSION_FORCE_MAX = 60.0

# Fragment pattern management
var _fragment_patterns = []
var _pattern_generator = null

# Fragment pools - organized by size category
var _fragment_pools = {
	"small": [],
	"medium": [],
	"large": []
}

# Active fragments tracking
var _active_fragments = []

# Fragment scene path
const ASTEROID_SCENE = "res://scenes/entities/asteroid.tscn"

# Track fragmentation events
var _fragmentation_history = []

func _ready() -> void:
	if ResourceLoader.exists("res://scripts/generators/fragment_pattern_generator.gd"):
		var PatternGeneratorClass = load("res://scripts/generators/fragment_pattern_generator.gd")
		_pattern_generator = PatternGeneratorClass.new()
		add_child(_pattern_generator)
	else:
		push_error("FragmentSpawner: Failed to load FragmentPatternGenerator")
	
	super._ready()

func _initialize() -> void:
	# Load asteroid scene
	_load_scene("asteroid", ASTEROID_SCENE)
	
	# Generate pre-computed patterns
	_generate_fragment_patterns()
	
	# Pre-generate fragment pools
	_generate_fragment_pools()
	
	_initialized = true
	spawner_ready.emit()

func _generate_fragment_patterns() -> void:
	# Get seed from game settings or SeedManager
	var seed_value = 12345
	if _game_settings:
		seed_value = _game_settings.get_seed()
	elif has_node("/root/SeedManager"):
		seed_value = SeedManager.get_seed()
	
	# Generate patterns for different asteroid sizes
	if _pattern_generator:
		_fragment_patterns = _pattern_generator.generate_pattern_collection(seed_value, patterns_per_size)
	
		if _debug_mode:
			print("FragmentSpawner: Generated " + str(_fragment_patterns.size()) + " fragment patterns")

# Generate all fragment pools
func _generate_fragment_pools() -> void:
	# Generate pools for different asteroid sizes
	_pre_generate_fragments("small", small_fragment_pool_size)
	_pre_generate_fragments("medium", medium_fragment_pool_size)
	_pre_generate_fragments("large", large_fragment_pool_size)

# Generate fragments of a specific size
func _pre_generate_fragments(size_category: String, count: int) -> void:
	# Convert size string to enum
	var size_enum = _size_string_to_enum(size_category)
	
	for i in range(count):
		var fragment = _create_fragment(size_category, size_enum, i)
		if fragment:
			_fragment_pools[size_category].append(fragment)
			
			# Hide the fragment initially
			fragment.visible = false

# Create a single fragment
func _create_fragment(size_category: String, size_enum: int, index: int) -> Node:
	if not _scene_cache.has("asteroid"):
		push_error("FragmentSpawner: Missing asteroid scene")
		return null
	
	var fragment = _scene_cache["asteroid"].instantiate()
	add_child(fragment)
	fragment.name = "Fragment_" + size_category + "_" + str(index)
	
	# Configure the fragment
	if fragment.has_method("setup"):
		# Use deterministic seed for consistency
		var base_seed
		if _game_settings:
			base_seed = _game_settings.get_seed()
		elif has_node("/root/SeedManager"):
			base_seed = SeedManager.get_seed()
		else:
			base_seed = 12345
			
		var seed_value = base_seed + (index * 100) + _size_enum_to_offset(size_enum)
		var rng = RandomNumberGenerator.new()
		rng.seed = seed_value
		
		var rotation_speed = rng.randf_range(-1.5, 1.5)
		var scale_factor = _get_scale_for_size(size_category)
		var variant = rng.randi() % 4  # 0-3 for asteroid variants
		
		# Setup asteroid with minimal parameters - position and velocity will be set when used
		fragment.setup(size_category, variant, scale_factor, rotation_speed)
	
	# Add to faction/group for proper gameplay handling
	if not fragment.is_in_group("asteroid_fragments"):
		fragment.add_to_group("asteroid_fragments")
	
	return fragment

# Spawn fragments for an asteroid
func spawn_fragments(asteroid_node: Node, asteroid_data: AsteroidData) -> Array:
	if not _initialized:
		await spawner_ready
	
	# Skip for small asteroids - they don't fragment
	if asteroid_data.size_category == AsteroidData.SizeCategory.SMALL:
		return []
	
	# Get fragment pattern for this asteroid
	var pattern = _get_pattern_for_asteroid(asteroid_data)
	
	# Create fragments based on pattern
	var fragments = []
	var fragment_count = 2  # Default value
	var fragment_sizes = []
	
	# Determine fragment properties based on pattern
	if pattern:
		fragment_count = pattern.fragment_count
		for i in range(pattern.fragment_count):
			if i < pattern.sizes.size():
				fragment_sizes.append(pattern.sizes[i])
	else:
		# Fallback properties if no pattern
		if asteroid_data.size_category == AsteroidData.SizeCategory.LARGE:
			fragment_sizes = ["medium", "small"]
		else:  # Medium asteroids
			fragment_sizes = ["small", "small"]
	
	# Get fragments from appropriate pools
	for i in range(fragment_count):
		var size = fragment_sizes[i] if i < fragment_sizes.size() else "small"
		var fragment = _get_fragment_from_pool(size)
		
		if fragment:
			fragments.append(fragment)
	
	# Configure fragments with pattern or default settings
	if pattern and fragments.size() > 0:
		_apply_pattern_to_fragments(pattern, fragments, asteroid_data, asteroid_node.global_position)
	else:
		_apply_default_fragment_config(fragments, asteroid_data, asteroid_node.global_position)
	
	# Play explosion/debris sound
	if _audio_manager:
		_audio_manager.play_sfx("explosion_debris", asteroid_node.global_position)
	
	# Record fragmentation for analysis (in debug mode)
	if _debug_mode:
		_record_fragmentation(asteroid_data, fragments.size())
	
	return fragments

# Get a specific fragment from pool
func _get_fragment_from_pool(pool_name: String) -> Node:
	var pool = _fragment_pools.get(pool_name, [])
	
	# First try to find an inactive fragment
	for fragment in pool:
		if is_instance_valid(fragment) and not fragment.visible:
			fragment.visible = true
			_active_fragments.append(fragment)
			return fragment
	
	# If no fragments available and auto-expand is enabled, create a new one
	if auto_expand_pools and _scene_cache.has("asteroid"):
		if _debug_mode:
			print("FragmentSpawner: Expanding " + pool_name + " pool")
			
		var size_enum = _size_string_to_enum(pool_name)
		var new_index = pool.size()
		var new_fragment = _create_fragment(pool_name, size_enum, new_index)
		
		if new_fragment:
			pool.append(new_fragment)
			_fragment_pools[pool_name] = pool
			new_fragment.visible = true
			_active_fragments.append(new_fragment)
			return new_fragment
	
	# If no fragments available, return null
	if _debug_mode:
		print("FragmentSpawner: No fragments available in " + pool_name + " pool!")
		
	return null

# Apply fragment pattern to fragments
func _apply_pattern_to_fragments(pattern: FragmentPatternData, fragments: Array, parent_data: AsteroidData, spawn_position: Vector2) -> void:
	for i in range(min(fragments.size(), pattern.positions.size())):
		var fragment = fragments[i]
		
		if not is_instance_valid(fragment):
			continue
		
		# Position with offset from parent
		fragment.global_position = spawn_position + pattern.positions[i]
		
		# Apply physics properties if this is a RigidBody2D
		if fragment is RigidBody2D:
			# Velocity based on pattern (parent velocity + pattern velocity)
			fragment.linear_velocity = parent_data.linear_velocity + pattern.velocities[i]
			
			# Rotation based on pattern
			fragment.angular_velocity = pattern.rotations[i]
			
		# Apply scale if the fragment has a scale property
		if fragment.has_method("set_scale_factor"):
			fragment.set_scale_factor(pattern.scale_factors[i])
		elif "scale" in fragment:
			var base_scale = fragment.scale.normalized()
			var uniform_scale = pattern.scale_factors[i]
			fragment.scale = base_scale * uniform_scale
		
		# Register with entity manager if available
		register_entity(fragment, "asteroid")

# Apply default configuration to fragments
func _apply_default_fragment_config(fragments: Array, parent_data: AsteroidData, spawn_position: Vector2) -> void:
	# Create a deterministic RNG for consistent results
	var rng = RandomNumberGenerator.new()
	rng.seed = parent_data.seed_value
	
	for i in range(fragments.size()):
		var fragment = fragments[i]
		
		if not is_instance_valid(fragment):
			continue
		
		# Calculate fragment position with offset
		var angle = (TAU / fragments.size()) * i + rng.randf_range(-0.3, 0.3)
		var distance = rng.randf_range(10, 30) * parent_data.scale_factor
		fragment.global_position = spawn_position + Vector2(cos(angle), sin(angle)) * distance
		
		# Apply physics properties if this is a RigidBody2D
		if fragment is RigidBody2D:
			# Generate random velocity (inherit parent velocity + explosion force)
			var explosion_dir = Vector2(cos(angle), sin(angle))
			var explosion_force = rng.randf_range(EXPLOSION_FORCE_MIN, EXPLOSION_FORCE_MAX)
			fragment.linear_velocity = parent_data.linear_velocity + explosion_dir * explosion_force
			
			# Random rotation
			fragment.angular_velocity = rng.randf_range(-1.5, 1.5)
		
		# Register with entity manager if available
		register_entity(fragment, "asteroid")

# Return a fragment to the pool
func return_fragment(fragment: Node) -> void:
	if not is_instance_valid(fragment):
		return
	
	# Hide the fragment
	fragment.visible = false
	
	# Reset state
	if fragment is RigidBody2D:
		fragment.linear_velocity = Vector2.ZERO
		fragment.angular_velocity = 0.0
	
	# Remove from active fragments list
	var index = _active_fragments.find(fragment)
	if index >= 0:
		_active_fragments.remove_at(index)

# Spawn fragments at a specific position
func spawn_fragments_at(position: Vector2, size_category: String, parent_velocity: Vector2 = Vector2.ZERO) -> Array:
	if not _initialized:
		await spawner_ready
	
	# Skip for small asteroids
	if size_category == "small":
		return []
	
	# Create temporary asteroid data
	var temp_asteroid = AsteroidData.new(
		0, # temp ID
		position,
		_get_deterministic_seed(position), # deterministic seed
		_size_string_to_enum(size_category)
	)
	temp_asteroid.linear_velocity = parent_velocity
	
	# Determine fragments to spawn
	var fragment_count = 2  # Default
	var fragment_sizes = []
	
	if size_category == "large":
		fragment_count = 2
		fragment_sizes = ["medium", "small"]
	else:  # "medium"
		fragment_count = 2
		fragment_sizes = ["small", "small"]
	
	# Get fragments from pools
	var fragments = []
	for i in range(fragment_count):
		var size = fragment_sizes[i] if i < fragment_sizes.size() else "small"
		var fragment = _get_fragment_from_pool(size)
		if fragment:
			fragments.append(fragment)
	
	# Apply default configuration
	_apply_default_fragment_config(fragments, temp_asteroid, position)
	
	return fragments

# Get the appropriate fragment pattern for an asteroid
func _get_pattern_for_asteroid(asteroid_data: AsteroidData) -> FragmentPatternData:
	# Initialize patterns if needed
	if _fragment_patterns.is_empty() and _pattern_generator:
		_generate_fragment_patterns()
	
	# Skip if no patterns or no generator
	if _fragment_patterns.is_empty() or not _pattern_generator:
		return null
	
	# Use the appropriate method to get patterns
	if _pattern_generator.has_method("get_pattern_for_asteroid"):
		return _pattern_generator.get_pattern_for_asteroid(_fragment_patterns, asteroid_data.size_category, asteroid_data.variant)
	
	# Fallback: Manual pattern selection
	var size_category = _get_size_category_string(asteroid_data.size_category)
	
	# Find matching pattern
	for pattern in _fragment_patterns:
		if pattern.source_size == size_category:
			# Use variant to select pattern
			var pattern_index = asteroid_data.variant % patterns_per_size
			if pattern.pattern_id % patterns_per_size == pattern_index:
				return pattern
	
	return null

# Clean up all active fragments
func clear_active_fragments() -> void:
	var active_copy = _active_fragments.duplicate()
	for fragment in active_copy:
		if is_instance_valid(fragment):
			return_fragment(fragment)

# Record fragmentation for debugging/analysis
func _record_fragmentation(asteroid_data: AsteroidData, fragment_count: int) -> void:
	if not _debug_mode:
		return
		
	_fragmentation_history.append({
		"time": Time.get_ticks_msec(),
		"asteroid_id": asteroid_data.entity_id,
		"size_category": asteroid_data.size_category,
		"position": asteroid_data.position,
		"fragment_count": fragment_count
	})
	
	# Limit history size
	if _fragmentation_history.size() > 100:
		_fragmentation_history.remove_at(0)

# Get deterministic seed from position
func _get_deterministic_seed(position: Vector2) -> int:
	var base_seed = 12345
	if _game_settings:
		base_seed = _game_settings.get_seed()
	elif has_node("/root/SeedManager"):
		base_seed = SeedManager.get_seed()
	
	# Create deterministic seed based on position
	return base_seed + int(position.x * 100) + int(position.y * 100)

# Helper functions

# Convert size category enum to string
func _get_size_category_string(size_category: int) -> String:
	match size_category:
		AsteroidData.SizeCategory.SMALL: return "small"
		AsteroidData.SizeCategory.MEDIUM: return "medium"
		AsteroidData.SizeCategory.LARGE: return "large"
		_: return "medium"

# Convert size string to enum
func _size_string_to_enum(size_string: String) -> int:
	match size_string:
		"small": return AsteroidData.SizeCategory.SMALL
		"medium": return AsteroidData.SizeCategory.MEDIUM
		"large": return AsteroidData.SizeCategory.LARGE
		_: return AsteroidData.SizeCategory.MEDIUM

# Get scale factor based on size
func _get_scale_for_size(size_category: String) -> float:
	match size_category:
		"small": return 0.5
		"medium": return 1.0
		"large": return 1.5
		_: return 1.0

# Get unique identifier offset based on size enum
func _size_enum_to_offset(size_enum: int) -> int:
	match size_enum:
		AsteroidData.SizeCategory.SMALL: return 1000
		AsteroidData.SizeCategory.MEDIUM: return 2000
		AsteroidData.SizeCategory.LARGE: return 3000
		_: return 0
