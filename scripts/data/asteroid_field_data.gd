extends EntityData
class_name AsteroidFieldData

# Field properties
var field_radius: float = 400.0
var asteroid_count: int = 0
var min_asteroids: int = 8
var max_asteroids: int = 15
var min_distance_between: float = 60.0
var size_variation: float = 0.4

# Distribution of asteroid sizes (0-1 scale)
var small_asteroid_chance: float = 0.3
var medium_asteroid_chance: float = 0.5
var large_asteroid_chance: float = 0.2

# Field physics
var min_linear_speed: float = 5.0
var max_linear_speed: float = 30.0
var max_rotation_speed: float = 0.5

# The actual asteroid data in this field
var asteroids: Array[AsteroidData] = []

func _init() -> void:
	super._init()
	entity_type = "asteroid_field"

# Generate asteroid distribution based on field properties
func generate_asteroid_distribution(rng: RandomNumberGenerator) -> void:
	# Determine number of asteroids
	asteroid_count = rng.randi_range(min_asteroids, max_asteroids)
	
	# Adjust distribution based on randomness within bounds
	small_asteroid_chance = rng.randf_range(0.25, 0.35)
	medium_asteroid_chance = rng.randf_range(0.45, 0.55)
	large_asteroid_chance = 1.0 - small_asteroid_chance - medium_asteroid_chance

# Override to implement a proper copy
func duplicate() -> AsteroidFieldData:
	var copy = super.duplicate() as AsteroidFieldData
	copy.field_radius = field_radius
	copy.asteroid_count = asteroid_count
	copy.min_asteroids = min_asteroids
	copy.max_asteroids = max_asteroids
	copy.min_distance_between = min_distance_between
	copy.size_variation = size_variation
	copy.small_asteroid_chance = small_asteroid_chance
	copy.medium_asteroid_chance = medium_asteroid_chance
	copy.large_asteroid_chance = large_asteroid_chance
	copy.min_linear_speed = min_linear_speed
	copy.max_linear_speed = max_linear_speed
	copy.max_rotation_speed = max_rotation_speed
	
	# Deep copy asteroids array
	copy.asteroids = []
	for asteroid in asteroids:
		copy.asteroids.append(asteroid.duplicate())
	
	return copy
