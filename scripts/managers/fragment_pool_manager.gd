# scripts/managers/fragment_pool_manager.gd
extends Node
class_name FragmentPoolManager

signal pools_initialized

# Pool sizes
@export var small_fragment_pool_size: int = 20
@export var medium_fragment_pool_size: int = 15
@export var large_fragment_pool_size: int = 10
@export var patterns_per_size: int = 5

# Pool configuration
@export var auto_expand_pools: bool = true
@export var use_instancing: bool = true

# Fragment scene paths
const ASTEROID_SCENE = "res://scenes/entities/asteroid.tscn"

# Fragment pattern collection
var _fragment_patterns = []

# Fragment pools - organized by size category
var _fragment_pools = {
	"small": [],
	"medium": [],
	"large": []
}

# Active fragments tracking
var _active_fragments = []

# Initialization tracking
var _initialized: bool = false
var _initializing: bool = false

# References
var _seed_value: int = 0
var _asteroid_scene = null
var _pattern_generator = null
var _entity_manager = null
var _debug_mode: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	
	# Find GameSettings
	var main_scene = get_tree().current_scene
	var game_settings = main_scene.get_node_or_null("GameSettings")
	if game_settings:
		_debug_mode = game_settings.debug_mode
		_seed_value = game_settings.get_seed()
	
	if has_node("/root/SeedManager"):
		var seed_manager = get_node("/root/SeedManager")
		if seed_manager.has_signal("seed_changed") and not seed_manager.is_connected("seed_changed", _on_seed_changed):
			seed_manager.connect("seed_changed", _on_seed_changed)
		_seed_value = seed_manager.get_seed()
	
	if has_node("/root/EntityManager"):
		_entity_manager = get_node("/root/EntityManager")
	
	# Preload the asteroid scene
	_asteroid_scene = load(ASTEROID_SCENE)
	
	# Initialize pattern generator
	_pattern_generator = FragmentPatternGenerator.new(_seed_value)
	add_child(_pattern_generator)
	
	# Initialize after engine is ready
	call_deferred("initialize")

func _on_seed_changed(new_seed: int) -> void:
	_seed_value = new_seed
	_pattern_generator = FragmentPatternGenerator.new(new_seed)
	_regenerate_patterns()

func initialize() -> void:
	if _initialized or _initializing:
		return
	
	_initializing = true
	
	if _debug_mode:
		print("FragmentPoolManager: Initializing fragment pools")
	
	# Generate patterns first
	_generate_fragment_patterns()
	
	# Pre-generate fragment pools
	_generate_fragment_pools()
	
	_initialized = true
	_initializing = false
	
	if _debug_mode:
		_log_pool_stats()
	
	# Signal that all pools are initialized
	pools_initialized.emit()

# Generate fragment patterns for different asteroid sizes
func _generate_fragment_patterns() -> void:
	_fragment_patterns = _pattern_generator.generate_pattern_collection(_seed_value, patterns_per_size)
	
	if _debug_mode:
		print("FragmentPoolManager: Generated " + str(_fragment_patterns.size()) + " fragment patterns")

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
	if not _asteroid_scene:
		return null
	
	var fragment
	if use_instancing:
		fragment = _asteroid_scene.instantiate()
	else:
		# For testing only - direct Node2D creation if scene isn't available
		fragment = Node2D.new()
		fragment.name = "Fragment_" + size_category + "_" + str(index)
	
	add_child(fragment)
	
	# Configure the fragment
	if fragment.has_method("setup"):
		# Use different random values to create variety
		var rng = RandomNumberGenerator.new()
		rng.seed = _seed_value + (index * 100) + _size_enum_to_offset(size_enum)
		
		var rotation_speed = rng.randf_range(-1.5, 1.5)
		var scale_factor = _get_scale_for_size(size_category)
		var variant = rng.randi() % 4  # 0-3 for asteroid variants
		
		# Setup asteroid with minimal parameters - position and velocity will be set when used
		fragment.setup(size_category, variant, scale_factor, rotation_speed)
	
	# Add to faction/group for proper gameplay handling
	if not fragment.is_in_group("asteroid_fragments"):
		fragment.add_to_group("asteroid_fragments")
	
	return fragment

# Get a fragment from the pool
func get_fragment(from_asteroid: AsteroidData, pattern_index: int = -1) -> Node:
	if not _initialized:
		await initialize()
	
	# Determine the appropriate pool based on the source asteroid
	var size_category = _get_size_category_string(from_asteroid.size_category)
	
	# Determine appropriate fragment pattern based on asteroid properties
	var pattern = null
	if pattern_index >= 0 and pattern_index < _fragment_patterns.size():
		pattern = _fragment_patterns[pattern_index]
	else:
		pattern = _get_pattern_for_asteroid(from_asteroid)
	
	# Determine fragment pool based on pattern
	var desired_pools = []
	if pattern:
		# Get fragments as specified by the pattern
		for i in range(pattern.fragment_count):
			if i >= pattern.sizes.size():
				continue
				
			var fragment_size = pattern.sizes[i]
			if fragment_size in _fragment_pools:
				desired_pools.append(fragment_size)
	else:
		# Fallback to default fragment sizing if no pattern
		match from_asteroid.size_category:
			AsteroidData.SizeCategory.LARGE:
				desired_pools = ["medium", "small"]
			AsteroidData.SizeCategory.MEDIUM:
				desired_pools = ["small", "small"]
			_: # Small asteroids don't generate fragments by default
				return null
	
	# Get fragments from each desired pool
	var fragments = []
	for pool_name in desired_pools:
		var fragment = _get_fragment_from_pool(pool_name)
		if fragment:
			fragments.append(fragment)
	
	# Configure the fragments based on pattern if available
	if pattern and fragments.size() > 0:
		_apply_pattern_to_fragments(pattern, fragments, from_asteroid)
	else:
		# Apply default configuration
		_apply_default_fragment_config(fragments, from_asteroid)
	
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
	if auto_expand_pools and _asteroid_scene:
		if _debug_mode:
			print("FragmentPoolManager: Expanding " + pool_name + " pool")
			
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
		print("FragmentPoolManager: No fragments available in " + pool_name + " pool!")
		
	return null

# Apply fragment pattern to a set of fragments
func _apply_pattern_to_fragments(pattern: FragmentPatternData, fragments: Array, parent_asteroid: AsteroidData) -> void:
	for i in range(min(fragments.size(), pattern.positions.size())):
		var fragment = fragments[i]
		
		if not is_instance_valid(fragment):
			continue
		
		# Position with offset from parent
		fragment.global_position = parent_asteroid.position + pattern.positions[i]
		
		# Apply physics properties if this is a RigidBody2D
		if fragment is RigidBody2D:
			# Velocity based on pattern (parent velocity + pattern velocity)
			fragment.linear_velocity = parent_asteroid.linear_velocity + pattern.velocities[i]
			
			# Rotation based on pattern
			fragment.angular_velocity = pattern.rotations[i]
			
		# Apply scale if the fragment has a scale property
		if fragment.has_method("set_scale_factor"):
			fragment.set_scale_factor(pattern.scale_factors[i])
		elif "scale" in fragment:
			var base_scale = fragment.scale
			var uniform_scale = pattern.scale_factors[i]
			fragment.scale = Vector2(base_scale.x * uniform_scale, base_scale.y * uniform_scale)

# Apply default configuration to fragments
func _apply_default_fragment_config(fragments: Array, parent_asteroid: AsteroidData) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = parent_asteroid.seed_value
	
	for i in range(fragments.size()):
		var fragment = fragments[i]
		
		if not is_instance_valid(fragment):
			continue
		
		# Calculate fragment position with offset
		var angle = (TAU / fragments.size()) * i + rng.randf_range(-0.3, 0.3)
		var distance = rng.randf_range(10, 30) * parent_asteroid.scale_factor
		fragment.global_position = parent_asteroid.position + Vector2(cos(angle), sin(angle)) * distance
		
		# Apply physics properties if this is a RigidBody2D
		if fragment is RigidBody2D:
			# Generate random velocity (inherit parent velocity + explosion force)
			var explosion_dir = Vector2(cos(angle), sin(angle))
			var explosion_force = rng.randf_range(40, 60)
			fragment.linear_velocity = parent_asteroid.linear_velocity + explosion_dir * explosion_force
			
			# Random rotation
			fragment.angular_velocity = rng.randf_range(-1.5, 1.5)

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

# Get pattern for asteroid
func _get_pattern_for_asteroid(asteroid_data: AsteroidData) -> FragmentPatternData:
	for pattern in _fragment_patterns:
		# Skip patterns for wrong asteroid size
		var size_string = _get_size_category_string(asteroid_data.size_category)
		if pattern.source_size != size_string:
			continue
			
		# Get pattern based on asteroid variant
		var variant = asteroid_data.variant % patterns_per_size
		if variant == pattern.pattern_id % patterns_per_size:
			return pattern
	
	return null

# Spawn fragments for an asteroid without direct generation
func spawn_fragments_for_asteroid(asteroid_data: AsteroidData) -> Array:
	if not _initialized:
		await initialize()
	
	# No fragments for small asteroids
	if asteroid_data.size_category == AsteroidData.SizeCategory.SMALL:
		return []
	
	# Get fragments from pool
	var fragments = get_fragment(asteroid_data)
	
	# Register fragments with entity manager if available
	if _entity_manager and _entity_manager.has_method("register_entity"):
		for fragment in fragments:
			_entity_manager.register_entity(fragment, "asteroid")
	
	return fragments

# Clean up all active fragments
func clear_active_fragments() -> void:
	for fragment in _active_fragments:
		if is_instance_valid(fragment):
			return_fragment(fragment)

# Regenerate patterns when seed changes
func _regenerate_patterns() -> void:
	_fragment_patterns = _pattern_generator.generate_pattern_collection(_seed_value, patterns_per_size)
	
	if _debug_mode:
		print("FragmentPoolManager: Regenerated patterns with new seed")

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

# Debug logging
func _log_pool_stats() -> void:
	if not _debug_mode:
		return
		
	print("FragmentPoolManager: Fragment pool statistics:")
	print("- Small fragments: " + str(_fragment_pools.small.size()))
	print("- Medium fragments: " + str(_fragment_pools.medium.size()))
	print("- Large fragments: " + str(_fragment_pools.large.size()))
	print("- Fragment patterns: " + str(_fragment_patterns.size()))
