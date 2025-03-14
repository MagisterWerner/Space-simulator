extends RefCounted
class_name AsteroidDataGenerator

# Asteroid field constants
const FIELD_RADIUS_MIN = 350.0
const FIELD_RADIUS_MAX = 450.0
const MIN_ASTEROIDS = 8
const MAX_ASTEROIDS = 20
const MIN_DISTANCE_BETWEEN = 60.0

# Asteroid size constants
const SIZE_VARIATION = 0.4
const SMALL_ASTEROID_CHANCE = 0.3
const MEDIUM_ASTEROID_CHANCE = 0.5
const LARGE_ASTEROID_CHANCE = 0.2

# Movement parameters
const MAX_ROTATION_SPEED = 0.5
const MIN_LINEAR_SPEED = 5.0
const MAX_LINEAR_SPEED = 30.0

# Collision shape generation
const MIN_COLLISION_POINTS = 6
const MAX_COLLISION_POINTS = 12

# Internal state
var _seed_value: int = 0
var _rng: RandomNumberGenerator

# Initialize with seed
func _init(seed_value: int = 0):
	_seed_value = seed_value
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value

# Generate an asteroid field
func generate_asteroid_field(entity_id: int, position: Vector2, seed_value: int) -> AsteroidFieldData:
	# Set seed for deterministic generation
	_rng.seed = seed_value
	
	# Create asteroid field data
	var field_data = AsteroidFieldData.new(entity_id, position, seed_value)
	
	# Customize field properties
	field_data.field_radius = _rng.randf_range(FIELD_RADIUS_MIN, FIELD_RADIUS_MAX)
	
	# Adjust asteroid count based on a density factor
	var density = _rng.randf_range(0.8, 1.2)
	field_data.min_asteroids = int(MIN_ASTEROIDS * density)
	field_data.max_asteroids = int(MAX_ASTEROIDS * density)
	
	# Set size variation
	field_data.size_variation = SIZE_VARIATION * _rng.randf_range(0.8, 1.2)
	
	# Set minimum distance between asteroids
	field_data.min_distance_between = MIN_DISTANCE_BETWEEN * _rng.randf_range(0.9, 1.1)
	
	# Set probability values with slight randomization
	field_data.small_asteroid_chance = SMALL_ASTEROID_CHANCE * _rng.randf_range(0.9, 1.1)
	field_data.medium_asteroid_chance = MEDIUM_ASTEROID_CHANCE * _rng.randf_range(0.9, 1.1)
	field_data.large_asteroid_chance = LARGE_ASTEROID_CHANCE * _rng.randf_range(0.9, 1.1)
	
	# Normalize probabilities
	var total = field_data.small_asteroid_chance + field_data.medium_asteroid_chance + field_data.large_asteroid_chance
	field_data.small_asteroid_chance /= total
	field_data.medium_asteroid_chance /= total
	field_data.large_asteroid_chance /= total
	
	# Set movement parameters
	field_data.max_rotation_speed = MAX_ROTATION_SPEED * _rng.randf_range(0.8, 1.2)
	field_data.min_linear_speed = MIN_LINEAR_SPEED * _rng.randf_range(0.9, 1.1)
	field_data.max_linear_speed = MAX_LINEAR_SPEED * _rng.randf_range(0.9, 1.1)
	
	return field_data

# Populate an asteroid field with asteroids
func populate_asteroid_field(field_data: AsteroidFieldData, world_data: WorldData) -> void:
	# Calculate spawn positions based on field parameters
	var positions = field_data.calculate_spawn_positions()
	
	# Generate asteroids for each position
	var count = 0
	for pos_data in positions:
		var asteroid_id = world_data.get_next_entity_id()
		var asteroid_seed = field_data.seed_value + count * 100
		
		# Create asteroid data
		var asteroid = _generate_asteroid(
			asteroid_id, 
			field_data.position + pos_data.position, 
			asteroid_seed,
			pos_data.size
		)
		
		# Apply position-specific attributes
		asteroid.scale_factor = pos_data.scale
		asteroid.rotation_speed = pos_data.rotation_speed
		asteroid.linear_velocity = pos_data.velocity
		asteroid.variant = pos_data.variant
		
		# Set field association
		asteroid.field_id = field_data.entity_id
		
		# Add to field
		field_data.add_asteroid(asteroid)
		count += 1
	
	if positions.is_empty() and field_data.min_asteroids > 0:
		# Fallback - generate at least one asteroid
		var asteroid_id = world_data.get_next_entity_id()
		var asteroid = _generate_asteroid(
			asteroid_id,
			field_data.position,
			field_data.seed_value + 999,
			AsteroidData.SizeCategory.MEDIUM
		)
		field_data.add_asteroid(asteroid)

# Generate a single asteroid
func _generate_asteroid(entity_id: int, position: Vector2, seed_value: int, 
						size_category: int = AsteroidData.SizeCategory.MEDIUM) -> AsteroidData:
	# Set seed for deterministic generation
	_rng.seed = seed_value
	
	# Create asteroid data
	var asteroid_data = AsteroidData.new(
		entity_id,
		position,
		seed_value,
		size_category
	)
	
	# Set variant
	asteroid_data.variant = _rng.randi_range(0, 3)
	
	# Generate rotation and movement
	asteroid_data.rotation_speed = _rng.randf_range(-0.5, 0.5)
	var angle = _rng.randf() * TAU
	var speed = _rng.randf_range(5.0, 25.0)
	asteroid_data.linear_velocity = Vector2(cos(angle), sin(angle)) * speed
	asteroid_data.angular_velocity = _rng.randf_range(-0.2, 0.2)
	
	# Generate collision shape
	_generate_collision_shape(asteroid_data)
	
	return asteroid_data

# Generate collision shape points for the asteroid
func _generate_collision_shape(asteroid_data: AsteroidData) -> void:
	_rng.seed = asteroid_data.seed_value + 12345
	
	# Determine number of points based on size
	var num_points
	match asteroid_data.size_category:
		AsteroidData.SizeCategory.SMALL:
			num_points = _rng.randi_range(MIN_COLLISION_POINTS, MIN_COLLISION_POINTS + 2)
		AsteroidData.SizeCategory.LARGE:
			num_points = _rng.randi_range(MAX_COLLISION_POINTS - 2, MAX_COLLISION_POINTS)
		_: # MEDIUM
			num_points = _rng.randi_range(MIN_COLLISION_POINTS + 2, MAX_COLLISION_POINTS - 2)
	
	# Generate points around a circle with random distance variation
	var points = PackedVector2Array()
	var radius = asteroid_data.radius
	
	for i in range(num_points):
		var angle = i * TAU / num_points
		var distance_variation = _rng.randf_range(0.8, 1.2)
		var point_radius = radius * distance_variation
		
		var x = cos(angle) * point_radius
		var y = sin(angle) * point_radius
		
		points.append(Vector2(x, y))
	
	asteroid_data.collision_points = points

# Generate an asteroid fragment from a parent asteroid
func generate_asteroid_fragment(parent_asteroid: AsteroidData, fragment_pattern_data = null) -> AsteroidData:
	# Get the next available ID
	var fragment_id = parent_asteroid.entity_id * 10 + _rng.randi_range(1, 9)
	var fragment_seed = parent_asteroid.seed_value + fragment_id
	_rng.seed = fragment_seed
	
	# Determine fragment size (smaller than parent)
	var fragment_size
	match parent_asteroid.size_category:
		AsteroidData.SizeCategory.LARGE:
			fragment_size = AsteroidData.SizeCategory.MEDIUM if _rng.randf() < 0.7 else AsteroidData.SizeCategory.SMALL
		AsteroidData.SizeCategory.MEDIUM:
			fragment_size = AsteroidData.SizeCategory.SMALL
		_:
			fragment_size = AsteroidData.SizeCategory.SMALL
	
	# Create fragment
	var fragment = AsteroidData.new(
		fragment_id,
		parent_asteroid.position,
		fragment_seed,
		fragment_size
	)
	
	# Apply pattern data if provided
	if fragment_pattern_data != null:
		var fragment_index = _rng.randi() % fragment_pattern_data.positions.size()
		
		# Position with offset from parent
		fragment.position = parent_asteroid.position + fragment_pattern_data.positions[fragment_index]
		
		# Velocity based on pattern
		fragment.linear_velocity = parent_asteroid.linear_velocity + fragment_pattern_data.velocities[fragment_index]
		
		# Rotation based on pattern
		fragment.rotation_speed = fragment_pattern_data.rotations[fragment_index]
		
		# Scale based on pattern
		var size_key = fragment_pattern_data.sizes[fragment_index]
		fragment.size_category = _size_string_to_category(size_key)
		fragment.scale_factor = fragment_pattern_data.scale_factors[fragment_index]
	else:
		# Generate random position offset
		var offset_angle = _rng.randf() * TAU
		var offset_distance = _rng.randf_range(10, 30) * parent_asteroid.scale_factor
		fragment.position += Vector2(cos(offset_angle), sin(offset_angle)) * offset_distance
		
		# Generate random velocity (inherit parent velocity + explosion force)
		var explosion_dir = Vector2(cos(offset_angle), sin(offset_angle))
		var explosion_force = _rng.randf_range(40, 60)
		fragment.linear_velocity = parent_asteroid.linear_velocity + explosion_dir * explosion_force
		
		# Random rotation
		fragment.rotation_speed = _rng.randf_range(-1.5, 1.5)
		
		# Scale based on size category
		match fragment_size:
			AsteroidData.SizeCategory.SMALL: 
				fragment.scale_factor = 0.5 * _rng.randf_range(0.9, 1.1)
			AsteroidData.SizeCategory.MEDIUM: 
				fragment.scale_factor = 0.7 * _rng.randf_range(0.9, 1.1)
	
	# Inherit field ID
	fragment.field_id = parent_asteroid.field_id
	
	# Generate collision shape
	_generate_collision_shape(fragment)
	
	return fragment

# Helper to convert size string to category enum
func _size_string_to_category(size_string: String) -> int:
	match size_string:
		"small": return AsteroidData.SizeCategory.SMALL
		"medium": return AsteroidData.SizeCategory.MEDIUM
		"large": return AsteroidData.SizeCategory.LARGE
		_: return AsteroidData.SizeCategory.SMALL
