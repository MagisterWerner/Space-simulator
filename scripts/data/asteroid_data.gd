extends EntityData
class_name AsteroidData

# Core asteroid properties
enum SizeCategory { SMALL, MEDIUM, LARGE }

# Asteroid properties
var size_category: String = "medium"  # Using string for compatibility with existing code
var numeric_size: int = SizeCategory.MEDIUM  # Numeric representation
var points_value: int = 100
var health: float = 35.0
var mass: float = 3.0

# Physical properties
var velocity: Vector2 = Vector2.ZERO
var angular_velocity: float = 0.0
var variant: int = 0  # For visual variety

# Reference to parent field or source
var field_id: int = -1  # ID of parent asteroid field, if any
var parent_asteroid_id: int = -1  # ID of parent asteroid if this is a fragment

func _init() -> void:
	super._init()
	entity_type = "asteroid"

# Get physical properties as a dictionary
func get_physics_properties() -> Dictionary:
	return {
		"velocity": velocity,
		"angular_velocity": angular_velocity,
		"mass": mass
	}

# Override clone to implement a proper deep copy
func clone() -> AsteroidData:
	var copy = super.clone() as AsteroidData
	copy.size_category = size_category
	copy.numeric_size = numeric_size
	copy.points_value = points_value
	copy.health = health
	copy.mass = mass
	copy.velocity = velocity
	copy.angular_velocity = angular_velocity
	copy.variant = variant
	copy.field_id = field_id
	copy.parent_asteroid_id = parent_asteroid_id
	return copy
	
# Convert size category string to numeric value
func set_size_from_string(size_string: String) -> void:
	size_category = size_string
	match size_string:
		"small":
			numeric_size = SizeCategory.SMALL
			health = 15.0
			mass = 1.5
			points_value = 50
		"medium":
			numeric_size = SizeCategory.MEDIUM
			health = 35.0
			mass = 3.0
			points_value = 100
		"large":
			numeric_size = SizeCategory.LARGE
			health = 70.0
			mass = 6.0
			points_value = 200
		_:
			# Default to medium if unknown
			numeric_size = SizeCategory.MEDIUM
			health = 35.0
			mass = 3.0
			points_value = 100
