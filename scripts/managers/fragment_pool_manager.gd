extends Node
class_name FragmentPoolManager

signal pools_initialized

# Pool configuration
@export var small_fragment_pool_size: int = 20
@export var medium_fragment_pool_size: int = 15
@export var large_fragment_pool_size: int = 10
@export var auto_expand_pools: bool = true

# Fragment pools - organized by size category
var _fragment_pools = {
	"small": [],
	"medium": [],
	"large": []
}

# Active fragments tracking
var _active_fragments = []

# Scene reference
var _asteroid_scene = null
const ASTEROID_SCENE_PATH = "res://scenes/entities/asteroid.tscn"

# Initialization tracking
var _initialized: bool = false
var _initializing: bool = false

# Fragment pattern reference
var _fragment_patterns = []
var _pattern_generator = null

# Debug mode
var _debug_mode: bool = false
var _game_settings = null
var _entity_manager = null

# Explosion parameters
const EXPLOSION_FORCE_MIN = 40.0
const EXPLOSION_FORCE_MAX = 60.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	
	# Find game settings
	var main_scene = get_tree().current_scene
	_game_settings = main_scene.get_node_or_null("GameSettings")
	if _game_settings:
		_debug_mode = _game_settings.debug_mode
	
	# Find entity manager
	_entity_manager = get_node_or_null("/root/EntityManager")
	
	# Initialize after engine is ready
	call_deferred("initialize")

func initialize() -> void:
	if _initialized or _initializing:
		return
	
	_initializing = true
	
	if _debug_mode:
		print("FragmentPoolManager: Initializing fragment pools")
	
	# Load asteroid scene
	_load_asteroid_scene()
	
	# Create pattern generator if needed
	_initialize_pattern_generator()
	
	# Generate fragment pools
	_generate_fragment_pools()
	
	# Mark as initialized
	_initialized = true
	_initializing = false
	
	if _debug_mode:
		print("FragmentPoolManager: Fragment pools initialized")
	
	# Signal that all pools are initialized
	pools_initialized.emit()

func _load_asteroid_scene() -> void:
	if ResourceLoader.exists(ASTEROID_SCENE_PATH):
		_asteroid_scene = load(ASTEROID_SCENE_PATH)
	else:
		push_error("FragmentPoolManager: Could not find asteroid scene")

func _initialize_pattern_generator() -> void:
	# Check if FragmentPatternGenerator exists
	if ResourceLoader.exists("res://scripts/generators/fragment_pattern_generator.gd"):
		var GeneratorClass = load("res://scripts/generators/fragment_pattern_generator.gd")
		_pattern_generator = GeneratorClass.new()
		add_child(_pattern_generator)
		
		# Generate patterns
		var seed_value = 12345
		if _game_settings:
			seed_value = _game_settings.get_seed()
		elif has_node("/root/SeedManager"):
			seed_value = SeedManager.get_seed()
			
		_fragment_patterns = _pattern_generator.generate_pattern_collection(seed_value)
	else:
		print("FragmentPoolManager: FragmentPatternGenerator not found. Using basic fragment generation.")

func _generate_fragment_pools() -> void:
	# Generate pools for different fragment sizes
	_pre_generate_fragments("small", small_fragment_pool_size)
	_pre_generate_fragments("medium", medium_fragment_pool_size)
	_pre_generate_fragments("large", large_fragment_pool_size)

func _pre_generate_fragments(size_category: String, count: int) -> void:
	if not _asteroid_scene:
		push_error("FragmentPoolManager: Cannot generate fragments - missing asteroid scene")
		return
	
	for i in range(count):
		var fragment = _create_fragment(size_category, i)
		if fragment:
			_fragment_pools[size_category].append(fragment)
			
			# Hide the fragment initially
			fragment.visible = false

func _create_fragment(size_category: String, index: int) -> Node:
	if not _asteroid_scene:
		return null
	
	# Instantiate fragment from asteroid scene
	var fragment = _asteroid_scene.instantiate()
	add_child(fragment)
	fragment.name = "Fragment_" + size_category + "_" + str(index)
	
	# Configure the fragment
	if fragment.has_method("setup"):
		# Use deterministic seed for consistency
		var base_seed = 0
		if _game_settings:
			base_seed = _game_settings.get_seed()
		elif has_node("/root/SeedManager"):
			base_seed = SeedManager.get_seed()
		else:
			base_seed = 12345
			
		var seed_value = base_seed + (index * 100) + _get_size_offset(size_category)
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

# Main API: Spawn fragments for an asteroid
func spawn_fragments_for_asteroid(asteroid_data: AsteroidData) -> Array:
	if not _initialized:
		await initialize()
	
	# Skip for small asteroids - they don't fragment
	if asteroid_data.size_category == AsteroidData.SizeCategory.SMALL:
		return []
	
	# Convert size category to string
	var size_category = _size_enum_to_string(asteroid_data.size_category)
	
	# Determine fragment properties
	var fragment_count = 2  # Default
	var fragment_sizes = []
	
	if size_category == "large":
		fragment_sizes = ["medium", "small"]
	else:  # Medium
		fragment_sizes = ["small", "small"]
	
	# Get pattern for this asteroid if possible
	var pattern = null
	if _pattern_generator and not _fragment_patterns.is_empty():
		pattern = _get_pattern_for_asteroid(asteroid_data)
	
	# Get fragments from pools
	var fragments = []
	for i in range(fragment_count):
		var size = fragment_sizes[i] if i < fragment_sizes.size() else "small"
		var fragment = _get_fragment_from_pool(size)
		
		if fragment:
			fragments.append(fragment)
	
	# Configure fragments with pattern or default settings
	if pattern and fragments.size() > 0:
		_apply_pattern_to_fragments(pattern, fragments, asteroid_data)
	else:
		_apply_default_fragment_config(fragments, asteroid_data)
	
	# Record fragmentation for analysis (in debug mode)
	if _debug_mode:
		print("FragmentPoolManager: Generated " + str(fragments.size()) + " fragments for asteroid " + str(asteroid_data.entity_id))
	
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
			
		var new_index = pool.size()
		var new_fragment = _create_fragment(pool_name, new_index)
		
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

# Get pattern for asteroid
func _get_pattern_for_asteroid(asteroid_data: AsteroidData) -> Object:
	if _fragment_patterns.is_empty() or not _pattern_generator:
		return null
		
	var size_string = _size_enum_to_string(asteroid_data.size_category)
	
	# Find matching pattern
	if _pattern_generator.has_method("get_pattern_for_asteroid"):
		return _pattern_generator.get_pattern_for_asteroid(_fragment_patterns, asteroid_data.size_category, asteroid_data.variant)
	
	# Fallback: find pattern ourselves
	for pattern in _fragment_patterns:
		if pattern.has_method("get_source_size") and pattern.get_source_size() == size_string:
			# Use variant to select pattern
			var pattern_index = asteroid_data.variant % _fragment_patterns.size()
			if pattern.get_pattern_id() == pattern_index:
				return pattern
	
	return null

# Apply pattern to fragments
func _apply_pattern_to_fragments(pattern, fragments: Array, parent_data: AsteroidData) -> void:
	# Grab appropriate pattern properties
	var positions = []
	var velocities = []
	var rotations = []
	var scale_factors = []
	
	# Extract pattern data based on available methods/properties
	if pattern.has_method("get_positions") and pattern.has_method("get_velocities"):
		positions = pattern.get_positions()
		velocities = pattern.get_velocities()
		rotations = pattern.get_rotations() if pattern.has_method("get_rotations") else []
		scale_factors = pattern.get_scale_factors() if pattern.has_method("get_scale_factors") else []
	elif "positions" in pattern and "velocities" in pattern:
		positions = pattern.positions
		velocities = pattern.velocities
		rotations = pattern.rotations if "rotations" in pattern else []
		scale_factors = pattern.scale_factors if "scale_factors" in pattern else []
	
	# Apply pattern to fragments
	for i in range(min(fragments.size(), positions.size())):
		var fragment = fragments[i]
		
		if not is_instance_valid(fragment):
			continue
		
		# Position with offset from parent
		fragment.global_position = parent_data.position + positions[i]
		
		# Apply physics properties if this is a RigidBody2D
		if fragment is RigidBody2D:
			# Velocity based on pattern (parent velocity + pattern velocity)
			fragment.linear_velocity = parent_data.linear_velocity + velocities[i]
			
			# Rotation based on pattern
			if i < rotations.size():
				fragment.angular_velocity = rotations[i]
			
		# Apply scale if the fragment has a scale property
		if "scale" in fragment and i < scale_factors.size():
			var base_scale = fragment.scale.normalized()
			var uniform_scale = scale_factors[i]
			fragment.scale = base_scale * uniform_scale
		
		# Register with entity manager if available
		if _entity_manager and _entity_manager.has_method("register_entity"):
			_entity_manager.register_entity(fragment, "asteroid")

# Apply default configuration to fragments
func _apply_default_fragment_config(fragments: Array, parent_data: AsteroidData) -> void:
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
		fragment.global_position = parent_data.position + Vector2(cos(angle), sin(angle)) * distance
		
		# Apply physics properties if this is a RigidBody2D
		if fragment is RigidBody2D:
			# Generate random velocity (inherit parent velocity + explosion force)
			var explosion_dir = Vector2(cos(angle), sin(angle))
			var explosion_force = rng.randf_range(EXPLOSION_FORCE_MIN, EXPLOSION_FORCE_MAX)
			fragment.linear_velocity = parent_data.linear_velocity + explosion_dir * explosion_force
			
			# Random rotation
			fragment.angular_velocity = rng.randf_range(-1.5, 1.5)
		
		# Register with entity manager if available
		if _entity_manager and _entity_manager.has_method("register_entity"):
			_entity_manager.register_entity(fragment, "asteroid")

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

# Clean up all active fragments
func clear_active_fragments() -> void:
	var active_copy = _active_fragments.duplicate()
	for fragment in active_copy:
		if is_instance_valid(fragment):
			return_fragment(fragment)

# UTILITY METHODS

# Convert size enum to string
func _size_enum_to_string(size_enum: int) -> String:
	if size_enum == 0: # AsteroidData.SizeCategory.SMALL
		return "small"
	elif size_enum == 1: # AsteroidData.SizeCategory.MEDIUM
		return "medium"
	elif size_enum == 2: # AsteroidData.SizeCategory.LARGE
		return "large"
	return "medium"

# Get offset value based on size
func _get_size_offset(size_category: String) -> int:
	match size_category:
		"small": return 1000
		"medium": return 2000
		"large": return 3000
	return 0

# Get scale factor for a size
func _get_scale_for_size(size_category: String) -> float:
	match size_category:
		"small": return 0.5
		"medium": return 1.0
		"large": return 1.5
	return 1.0
