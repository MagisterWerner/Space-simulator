extends EntityData
class_name AsteroidData

# Asteroid size categories
enum SizeCategory {
	SMALL,
	MEDIUM,
	LARGE
}

# Core properties
var size_category: int = SizeCategory.MEDIUM
var variant: int = 0
var scale_factor: float = 1.0
var points_value: int = 100
var health: float = 100.0
var texture_seed: int = 0

# Physics properties
var mass: float = 3.0
var rotation_speed: float = 0.0
var linear_velocity: Vector2 = Vector2.ZERO
var angular_velocity: float = 0.0

# Shape data - for collision/physics
var collision_points: PackedVector2Array
var radius: float = 16.0

# Field association (if part of a field)
var field_id: int = -1

func _init(p_entity_id: int = 0, 
		   p_position: Vector2 = Vector2.ZERO, 
		   p_seed: int = 0,
		   p_size: int = SizeCategory.MEDIUM) -> void:
	super._init(p_entity_id, "asteroid", p_position, p_seed)
	size_category = p_size
	texture_seed = p_seed
	
	# Set default properties based on size category
	_initialize_size_properties()

# Initialize default properties based on size
func _initialize_size_properties() -> void:
	match size_category:
		SizeCategory.SMALL:
			health = 15.0
			mass = 1.5
			scale_factor = 0.5
			points_value = 50
			radius = 8.0
		SizeCategory.MEDIUM:
			health = 35.0
			mass = 3.0
			scale_factor = 1.0
			points_value = 100
			radius = 16.0
		SizeCategory.LARGE:
			health = 70.0
			mass = 6.0
			scale_factor = 1.5
			points_value = 200
			radius = 24.0

# Get size name as string
func get_size_name() -> String:
	match size_category:
		SizeCategory.SMALL: return "small"
		SizeCategory.MEDIUM: return "medium"
		SizeCategory.LARGE: return "large"
		_: return "unknown"

# Override duplicate for proper copying
func duplicate() -> AsteroidData:
	var copy = super.duplicate() as AsteroidData
	copy.size_category = size_category
	copy.variant = variant
	copy.scale_factor = scale_factor
	copy.points_value = points_value
	copy.health = health
	copy.texture_seed = texture_seed
	
	# Physics properties
	copy.mass = mass
	copy.rotation_speed = rotation_speed
	copy.linear_velocity = linear_velocity
	copy.angular_velocity = angular_velocity
	
	# Shape data
	copy.collision_points = collision_points.duplicate()
	copy.radius = radius
	
	# Field association
	copy.field_id = field_id
	
	return copy

# Generate fragment data based on this asteroid
func generate_fragment_data(fragment_count: int, explosion_force: float = 50.0) -> Array:
	var fragments = []
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value * 123 + 456
	
	# Determine fragment properties based on size
	var new_size = SizeCategory.SMALL
	var new_scale = scale_factor * 0.6
	
	if size_category == SizeCategory.LARGE:
		# Large asteroids produce medium and small fragments
		if fragment_count > 1:
			fragments.append(_create_fragment(SizeCategory.MEDIUM, 0.7, rng, explosion_force))
			fragments.append(_create_fragment(SizeCategory.SMALL, 0.5, rng, explosion_force))
		else:
			fragments.append(_create_fragment(SizeCategory.MEDIUM, 0.7, rng, explosion_force))
	elif size_category == SizeCategory.MEDIUM:
		# Medium asteroids produce small fragments
		for i in range(fragment_count):
			fragments.append(_create_fragment(SizeCategory.SMALL, 0.5, rng, explosion_force))
	
	return fragments

# Helper to create a single fragment
func _create_fragment(size: int, scale: float, rng: RandomNumberGenerator, force: float) -> AsteroidData:
	var fragment = AsteroidData.new()
	
	# Generate unique ID and seed
	fragment.entity_id = entity_id * 10 + rng.randi_range(1, 9)
	fragment.seed_value = seed_value + fragment.entity_id
	fragment.texture_seed = fragment.seed_value
	fragment.entity_type = "asteroid"
	
	# Position with slight offset
	var angle = rng.randf_range(0, TAU)
	var distance = rng.randf_range(10, 30) * scale_factor
	fragment.position = position + Vector2(cos(angle), sin(angle)) * distance
	
	# Size and scale
	fragment.size_category = size
	fragment.scale_factor = scale
	fragment._initialize_size_properties()
	
	# Physics properties
	fragment.rotation_speed = rng.randf_range(-1.5, 1.5)
	
	# Velocity: inherit parent velocity + explosion force
	var explosion_dir = Vector2(cos(angle), sin(angle))
	var explosion_speed = rng.randf_range(force * 0.8, force * 1.2)
	fragment.linear_velocity = linear_velocity + explosion_dir * explosion_speed
	fragment.angular_velocity = rng.randf_range(-1.5, 1.5)
	
	# Field association
	fragment.field_id = field_id
	
	return fragment

# Serialization helper
func to_dict() -> Dictionary:
	var base_dict = super.to_dict()
	
	var asteroid_dict = {
		"size_category": size_category,
		"variant": variant,
		"scale_factor": scale_factor,
		"points_value": points_value,
		"health": health,
		"texture_seed": texture_seed,
		"mass": mass,
		"rotation_speed": rotation_speed,
		"linear_velocity": {"x": linear_velocity.x, "y": linear_velocity.y},
		"angular_velocity": angular_velocity,
		"radius": radius,
		"field_id": field_id,
		"collision_points": _vector_array_to_dict(collision_points)
	}
	
	# Merge with base dictionary
	base_dict.merge(asteroid_dict, true)
	return base_dict

# Helper to serialize vector array
func _vector_array_to_dict(points: PackedVector2Array) -> Array:
	var result = []
	for point in points:
		result.append({"x": point.x, "y": point.y})
	return result

# Deserialization helper
static func from_dict(data: Dictionary) -> AsteroidData:
	var base_data = EntityData.from_dict(data)
	
	var asteroid_data = AsteroidData.new()
	asteroid_data.entity_id = base_data.entity_id
	asteroid_data.entity_type = base_data.entity_type
	asteroid_data.position = base_data.position
	asteroid_data.seed_value = base_data.seed_value
	asteroid_data.grid_cell = base_data.grid_cell
	asteroid_data.properties = base_data.properties
	
	# Asteroid-specific properties
	asteroid_data.size_category = data.get("size_category", SizeCategory.MEDIUM)
	asteroid_data.variant = data.get("variant", 0)
	asteroid_data.scale_factor = data.get("scale_factor", 1.0)
	asteroid_data.points_value = data.get("points_value", 100)
	asteroid_data.health = data.get("health", 100.0)
	asteroid_data.texture_seed = data.get("texture_seed", asteroid_data.seed_value)
	
	# Physics properties
	asteroid_data.mass = data.get("mass", 3.0)
	asteroid_data.rotation_speed = data.get("rotation_speed", 0.0)
	
	var vel = data.get("linear_velocity", {"x": 0, "y": 0})
	asteroid_data.linear_velocity = Vector2(vel.get("x", 0), vel.get("y", 0))
	
	asteroid_data.angular_velocity = data.get("angular_velocity", 0.0)
	
	# Shape data
	asteroid_data.radius = data.get("radius", 16.0)
	
	# Collision points
	var points_data = data.get("collision_points", [])
	asteroid_data.collision_points = PackedVector2Array()
	for point_dict in points_data:
		asteroid_data.collision_points.append(Vector2(point_dict.get("x", 0), point_dict.get("y", 0)))
	
	# Field association
	asteroid_data.field_id = data.get("field_id", -1)
	
	return asteroid_data
