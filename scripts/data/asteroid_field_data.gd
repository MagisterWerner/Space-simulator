extends EntityData
class_name AsteroidFieldData

# Field properties
var field_radius: float = 400.0
var min_asteroids: int = 8
var max_asteroids: int = 15
var min_distance_between: float = 60.0
var size_variation: float = 0.4

# Asteroid size probabilities
var small_asteroid_chance: float = 0.3
var medium_asteroid_chance: float = 0.5
var large_asteroid_chance: float = 0.2

# Movement parameters
var max_rotation_speed: float = 0.5
var min_linear_speed: float = 5.0 
var max_linear_speed: float = 30.0

# The actual generated asteroids in this field
var asteroids: Array = []

func _init(p_entity_id: int = 0, p_position: Vector2 = Vector2.ZERO, p_seed: int = 0) -> void:
	super._init(p_entity_id, "asteroid_field", p_position, p_seed)

# Add a generated asteroid to this field
func add_asteroid(asteroid_data: AsteroidData) -> void:
	asteroids.append(asteroid_data)
	asteroid_data.field_id = entity_id

# Count asteroids by size
func count_asteroids_by_size() -> Dictionary:
	var counts = {
		AsteroidData.SizeCategory.SMALL: 0,
		AsteroidData.SizeCategory.MEDIUM: 0,
		AsteroidData.SizeCategory.LARGE: 0
	}
	
	for asteroid in asteroids:
		counts[asteroid.size_category] += 1
	
	return counts

# Override duplicate for proper copying
func duplicate() -> AsteroidFieldData:
	var copy = super.duplicate() as AsteroidFieldData
	
	# Field properties
	copy.field_radius = field_radius
	copy.min_asteroids = min_asteroids
	copy.max_asteroids = max_asteroids
	copy.min_distance_between = min_distance_between
	copy.size_variation = size_variation
	
	# Asteroid chances
	copy.small_asteroid_chance = small_asteroid_chance
	copy.medium_asteroid_chance = medium_asteroid_chance
	copy.large_asteroid_chance = large_asteroid_chance
	
	# Movement parameters
	copy.max_rotation_speed = max_rotation_speed
	copy.min_linear_speed = min_linear_speed
	copy.max_linear_speed = max_linear_speed
	
	# Duplicate asteroids
	copy.asteroids = []
	for asteroid in asteroids:
		copy.asteroids.append(asteroid.duplicate())
	
	return copy

# Generate field shape parameters (purely for display or to assist generation)
func generate_field_shape_params() -> Dictionary:
	# Create a deterministic RNG
	var field_rng = RandomNumberGenerator.new()
	field_rng.seed = seed_value
	
	# Apply some variation to field radius
	var radius_factor = 1.0 + (field_rng.randf() * 0.4 - 0.2)
	var actual_radius = field_radius * radius_factor
	
	# Generate field shape factor
	var elongation = field_rng.randf_range(0.0, 0.3)
	var rotation = field_rng.randf() * TAU
	
	# Field debug color
	var debug_color = Color(
		field_rng.randf_range(0.5, 1.0),
		field_rng.randf_range(0.3, 0.7),
		field_rng.randf_range(0.0, 0.3),
		0.5
	)
	
	return {
		"radius": actual_radius,
		"elongation": elongation,
		"rotation": rotation,
		"debug_color": debug_color
	}

# Calculate spawn positions for asteroids (useful for asteroid spawner)
func calculate_spawn_positions() -> Array:
	var positions = []
	var field_rng = RandomNumberGenerator.new()
	field_rng.seed = seed_value
	
	# Get shape parameters
	var shape_params = generate_field_shape_params()
	var actual_radius = shape_params.radius
	var field_rotation = shape_params.rotation
	var field_elongation = shape_params.elongation
	
	# Determine asteroid count
	var asteroid_count = field_rng.randi_range(min_asteroids, max_asteroids)
	
	# Attempt to create asteroid positions
	var max_attempts = asteroid_count * 10
	var attempts = 0
	
	while positions.size() < asteroid_count and attempts < max_attempts:
		# Generate random position within field radius
		var distance = field_rng.randf() * actual_radius
		var angle = field_rng.randf() * TAU
		
		# Apply field elongation and rotation
		var stretched_x = cos(angle) * (1.0 - field_elongation)
		var stretched_y = sin(angle)
		var rotated_x = stretched_x * cos(field_rotation) - stretched_y * sin(field_rotation)
		var rotated_y = stretched_x * sin(field_rotation) + stretched_y * cos(field_rotation)
		
		var pos = Vector2(rotated_x, rotated_y) * distance
		
		# Check if position is valid (not too close to other asteroids)
		var valid_position = true
		for existing_pos in positions:
			if existing_pos.position.distance_to(pos) < min_distance_between:
				valid_position = false
				break
		
		if valid_position:
			# Determine size category
			var size_roll = field_rng.randf()
			var size_category
			
			if size_roll < small_asteroid_chance:
				size_category = AsteroidData.SizeCategory.SMALL
			elif size_roll < small_asteroid_chance + medium_asteroid_chance:
				size_category = AsteroidData.SizeCategory.MEDIUM
			else:
				size_category = AsteroidData.SizeCategory.LARGE
			
			var rotation_speed = field_rng.randf_range(-max_rotation_speed, max_rotation_speed)
			
			# Apply random variation to scale
			var base_scale = 1.0
			match size_category:
				AsteroidData.SizeCategory.SMALL: base_scale = 0.5
				AsteroidData.SizeCategory.MEDIUM: base_scale = 1.0
				AsteroidData.SizeCategory.LARGE: base_scale = 1.5
			
			var actual_scale = base_scale * (1.0 + (field_rng.randf() * size_variation * 2.0 - size_variation))
			
			# Generate random velocity
			var speed = field_rng.randf_range(min_linear_speed, max_linear_speed)
			var vel_angle = field_rng.randf() * TAU
			var velocity = Vector2(cos(vel_angle), sin(vel_angle)) * speed
			
			positions.append({
				"position": pos,
				"size": size_category,
				"scale": actual_scale,
				"rotation_speed": rotation_speed,
				"velocity": velocity,
				"variant": field_rng.randi_range(0, 3)
			})
		
		attempts += 1
	
	return positions

# Serialization helper
func to_dict() -> Dictionary:
	var base_dict = super.to_dict()
	
	var field_dict = {
		"field_radius": field_radius,
		"min_asteroids": min_asteroids,
		"max_asteroids": max_asteroids,
		"min_distance_between": min_distance_between,
		"size_variation": size_variation,
		"small_asteroid_chance": small_asteroid_chance,
		"medium_asteroid_chance": medium_asteroid_chance,
		"large_asteroid_chance": large_asteroid_chance,
		"max_rotation_speed": max_rotation_speed,
		"min_linear_speed": min_linear_speed,
		"max_linear_speed": max_linear_speed,
		"asteroids": []
	}
	
	# Serialize asteroids
	for asteroid in asteroids:
		field_dict.asteroids.append(asteroid.to_dict())
	
	# Merge with base dictionary
	base_dict.merge(field_dict, true)
	return base_dict

# Deserialization helper
static func from_dict(data: Dictionary) -> AsteroidFieldData:
	var base_data = EntityData.from_dict(data)
	
	var field_data = AsteroidFieldData.new()
	field_data.entity_id = base_data.entity_id
	field_data.entity_type = base_data.entity_type
	field_data.position = base_data.position
	field_data.seed_value = base_data.seed_value
	field_data.grid_cell = base_data.grid_cell
	field_data.properties = base_data.properties
	
	# Field-specific properties
	field_data.field_radius = data.get("field_radius", 400.0)
	field_data.min_asteroids = data.get("min_asteroids", 8)
	field_data.max_asteroids = data.get("max_asteroids", 15)
	field_data.min_distance_between = data.get("min_distance_between", 60.0)
	field_data.size_variation = data.get("size_variation", 0.4)
	
	# Asteroid chances
	field_data.small_asteroid_chance = data.get("small_asteroid_chance", 0.3)
	field_data.medium_asteroid_chance = data.get("medium_asteroid_chance", 0.5)
	field_data.large_asteroid_chance = data.get("large_asteroid_chance", 0.2)
	
	# Movement parameters
	field_data.max_rotation_speed = data.get("max_rotation_speed", 0.5)
	field_data.min_linear_speed = data.get("min_linear_speed", 5.0)
	field_data.max_linear_speed = data.get("max_linear_speed", 30.0)
	
	# Deserialize asteroids
	var asteroids_data = data.get("asteroids", [])
	for asteroid_dict in asteroids_data:
		var asteroid = AsteroidData.from_dict(asteroid_dict)
		field_data.asteroids.append(asteroid)
	
	return field_data
