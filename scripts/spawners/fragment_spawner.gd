# scripts/spawners/fragment_spawner.gd
extends EntitySpawnerBase
class_name FragmentSpawner

# Explosion parameters
const EXPLOSION_FORCE_MIN = 40.0
const EXPLOSION_FORCE_MAX = 60.0

# Fragment pattern management
var _fragment_patterns = []
var _pattern_generator = null
var _asteroid_spawner = null

# Track fragmentation events
var _fragmentation_history = []

func _ready() -> void:
	_pattern_generator = FragmentPatternGenerator.new()
	_find_asteroid_spawner()
	super._ready()

func _initialize() -> void:
	# Generate pre-computed patterns
	_generate_fragment_patterns()
	_initialized = true
	spawner_ready.emit()

func _find_asteroid_spawner() -> void:
	# Try to find existing asteroid spawner
	var spawners = get_tree().get_nodes_in_group("spawners")
	for spawner in spawners:
		if spawner is AsteroidSpawner:
			_asteroid_spawner = spawner
			return
	
	# Create a new one if needed
	if not _asteroid_spawner:
		_asteroid_spawner = AsteroidSpawner.new()
		_asteroid_spawner.name = "AsteroidSpawner"
		get_parent().call_deferred("add_child", _asteroid_spawner)
		await _asteroid_spawner.spawner_ready

func _generate_fragment_patterns() -> void:
	# Get seed from game settings
	var seed_value = 12345
	if _game_settings:
		seed_value = _game_settings.get_seed()
	
	# Generate patterns for different asteroid sizes
	_fragment_patterns = _pattern_generator.generate_pattern_collection(seed_value)
	
	if _debug_mode:
		print("FragmentSpawner: Generated " + str(_fragment_patterns.size()) + " fragment patterns")

# Spawn fragments for an asteroid using pre-generated patterns
func spawn_fragments(asteroid_node: Node, asteroid_data: AsteroidData) -> Array:
	if not _initialized:
		await spawner_ready
	
	if not _asteroid_spawner:
		_find_asteroid_spawner()
		if not _asteroid_spawner:
			push_error("FragmentSpawner: No asteroid spawner available")
			return []
	
	# Skip for small asteroids - they don't fragment
	if asteroid_data.size_category == AsteroidData.SizeCategory.SMALL:
		return []
	
	# Get fragment pattern for this asteroid
	var pattern = _get_pattern_for_asteroid(asteroid_data)
	if not pattern:
		# Fallback to direct fragmentation without pattern
		return _spawn_fragments_direct(asteroid_node, asteroid_data)
	
	# Create fragment data objects from pattern
	var fragments = []
	for i in range(pattern.fragment_count):
		var fragment_data = _create_fragment_data_from_pattern(asteroid_data, pattern, i)
		
		# Spawn asteroid from data
		var fragment = _asteroid_spawner.spawn_asteroid(fragment_data)
		if fragment:
			fragments.append(fragment)
	
	# Play explosion/debris sound
	if _audio_manager:
		_audio_manager.play_sfx("explosion_debris", asteroid_node.global_position)
	
	# Record fragmentation for analysis
	_record_fragmentation(asteroid_data, fragments.size())
	
	return fragments

# Spawn fragments directly without using patterns
func _spawn_fragments_direct(asteroid_node: Node, asteroid_data: AsteroidData) -> Array:
	# Determine how many fragments to spawn
	var fragment_count = 0
	var fragment_sizes = []
	
	if asteroid_data.size_category == AsteroidData.SizeCategory.LARGE:
		fragment_count = 2
		fragment_sizes = [
			AsteroidData.SizeCategory.MEDIUM,
			AsteroidData.SizeCategory.SMALL
		]
	elif asteroid_data.size_category == AsteroidData.SizeCategory.MEDIUM:
		fragment_count = 2
		fragment_sizes = [
			AsteroidData.SizeCategory.SMALL,
			AsteroidData.SizeCategory.SMALL
		]
	else:
		return [] # Small asteroids don't fragment
	
	# Create a random generator for positions and velocities
	var rng = RandomNumberGenerator.new()
	rng.seed = asteroid_data.seed_value + 12345
	
	var fragments = []
	for i in range(fragment_count):
		# Calculate fragment position with offset
		var angle = (TAU / fragment_count) * i + rng.randf_range(-0.3, 0.3)
		var distance = rng.randf_range(10, 30) * asteroid_data.scale_factor
		var fragment_pos = asteroid_data.position + Vector2(cos(angle), sin(angle)) * distance
		
		# Create unique ID
		var fragment_id = asteroid_data.entity_id * 10 + i + 1
		
		# Create asteroid data
		var fragment_data = AsteroidData.new(
			fragment_id,
			fragment_pos,
			asteroid_data.seed_value + fragment_id,
			fragment_sizes[i if i < fragment_sizes.size() else 0]
		)
		
		# Set physical properties
		fragment_data.variant = asteroid_data.variant
		
		# Scale based on size
		if fragment_data.size_category == AsteroidData.SizeCategory.MEDIUM:
			fragment_data.scale_factor = 0.7 * rng.randf_range(0.9, 1.1)
		else: # small
			fragment_data.scale_factor = 0.5 * rng.randf_range(0.9, 1.1)
		
		# Calculate velocity
		var explosion_force = rng.randf_range(EXPLOSION_FORCE_MIN, EXPLOSION_FORCE_MAX)
		var explosion_dir = Vector2(cos(angle), sin(angle))
		fragment_data.linear_velocity = asteroid_data.linear_velocity + explosion_dir * explosion_force
		
		# Set rotation
		fragment_data.rotation_speed = rng.randf_range(-1.5, 1.5)
		
		# Set field ID
		fragment_data.field_id = asteroid_data.field_id
		
		# Spawn fragment
		var fragment = _asteroid_spawner.spawn_asteroid(fragment_data)
		if fragment:
			fragments.append(fragment)
	
	# Record fragmentation for analysis
	_record_fragmentation(asteroid_data, fragments.size())
	
	return fragments

# Spawn fragments at a specific position
func spawn_fragments_at(position: Vector2, size_category: String, parent_velocity: Vector2 = Vector2.ZERO) -> Array:
	if not _initialized:
		await spawner_ready
	
	if not _asteroid_spawner:
		_find_asteroid_spawner()
		if not _asteroid_spawner:
			push_error("FragmentSpawner: No asteroid spawner available")
			return []
	
	# Convert size category string to enum
	var size_enum
	match size_category:
		"small": size_enum = AsteroidData.SizeCategory.SMALL
		"medium": size_enum = AsteroidData.SizeCategory.MEDIUM
		"large": size_enum = AsteroidData.SizeCategory.LARGE
		_: size_enum = AsteroidData.SizeCategory.MEDIUM
	
	# Skip for small asteroids
	if size_enum == AsteroidData.SizeCategory.SMALL:
		return []
	
	# Create temporary asteroid data
	var temp_asteroid = AsteroidData.new(
		0, # temp ID
		position,
		randi(), # random seed
		size_enum
	)
	temp_asteroid.linear_velocity = parent_velocity
	
	# Use direct spawning method
	return _spawn_fragments_direct(null, temp_asteroid)

# Get the appropriate fragment pattern for an asteroid
func _get_pattern_for_asteroid(asteroid_data: AsteroidData) -> FragmentPatternData:
	# Initialize patterns if needed
	if _fragment_patterns.is_empty():
		_generate_fragment_patterns()
	
	# Return pattern for this asteroid
	return _pattern_generator.get_pattern_for_asteroid(
		_fragment_patterns,
		asteroid_data.size_category,
		asteroid_data.variant
	)

# Create fragment data from a pattern
func _create_fragment_data_from_pattern(parent_data: AsteroidData, pattern: FragmentPatternData, index: int) -> AsteroidData:
	# Skip invalid indices
	if index >= pattern.positions.size():
		return null
	
	# Generate unique ID
	var fragment_id = parent_data.entity_id * 10 + index + 1
	
	# Create position from pattern
	var position = parent_data.position + pattern.positions[index]
	
	# Determine size category from pattern
	var size_string = pattern.sizes[index]
	var size_category
	match size_string:
		"small": size_category = AsteroidData.SizeCategory.SMALL
		"medium": size_category = AsteroidData.SizeCategory.MEDIUM
		"large": size_category = AsteroidData.SizeCategory.LARGE
		_: size_category = AsteroidData.SizeCategory.SMALL
	
	# Create asteroid data
	var fragment_data = AsteroidData.new(
		fragment_id,
		position,
		parent_data.seed_value + fragment_id,
		size_category
	)
	
	# Apply pattern properties
	fragment_data.scale_factor = pattern.scale_factors[index]
	fragment_data.rotation_speed = pattern.rotations[index]
	fragment_data.linear_velocity = parent_data.linear_velocity + pattern.velocities[index]
	fragment_data.variant = parent_data.variant
	fragment_data.field_id = parent_data.field_id
	
	return fragment_data

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
