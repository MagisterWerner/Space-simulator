extends RefCounted
class_name FragmentPatternGenerator

# Fragment pattern constants
const PATTERN_COUNT_PER_SIZE = 10
const EXPLOSION_FORCE_BASE = 50.0
const FRAGMENT_COUNT = {
	"large": 3,
	"medium": 2,
	"small": 0  # Small asteroids don't generate fragments
}

# Internal state
var _seed_value: int = 0
var _rng: RandomNumberGenerator

# Initialize with seed
func _init(seed_value: int = 0):
	_seed_value = seed_value
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value

# Generate a collection of fragment patterns for different asteroid sizes
func generate_pattern_collection(seed_value: int, pattern_count: int = PATTERN_COUNT_PER_SIZE) -> Array:
	var patterns = []
	
	# Generate patterns for different source sizes
	for source_size in ["large", "medium"]:
		for i in range(pattern_count):
			var pattern_id = i + (0 if source_size == "large" else pattern_count)
			var pattern = generate_for_size(seed_value, source_size, pattern_id)
			if pattern:
				patterns.append(pattern)
	
	return patterns

# Generate a fragment pattern for a specific asteroid size
func generate_for_size(seed_value: int, source_size: String, pattern_id: int) -> FragmentPatternData:
	# Set seed for deterministic generation
	_rng.seed = seed_value + pattern_id * 1000
	
	# Get fragment count for this size
	var fragment_count = FRAGMENT_COUNT.get(source_size, 0)
	if fragment_count == 0:
		return null
	
	# Create pattern with proper ID
	var pattern = FragmentPatternData.new(pattern_id, source_size, fragment_count)
	
	# Calculate base explosion force
	var base_force = EXPLOSION_FORCE_BASE
	if source_size == "large":
		base_force *= 1.2
	
	# Generate fragments with variations
	for i in range(fragment_count):
		# Vary position
		var angle = (TAU / fragment_count) * i + _rng.randf_range(-0.3, 0.3)
		var distance = _rng.randf_range(10, 30)
		var position = Vector2(cos(angle), sin(angle)) * distance
		
		# Vary velocity
		var explosion_dir = Vector2(cos(angle), sin(angle))
		var explosion_speed = _rng.randf_range(base_force * 0.8, base_force * 1.2)
		var velocity = explosion_dir * explosion_speed
		
		# Rotation and scale
		var rotation = _rng.randf_range(-1.5, 1.5)
		
		# Determine size
		var result_size
		if source_size == "large":
			if i == 0:
				result_size = "medium"
			else:
				result_size = _rng.randf() < 0.7 ? "medium" : "small"
		else:  # medium source
			result_size = "small"
		
		# Determine scale factor
		var scale_factor = 0.6
		if result_size == "medium":
			scale_factor = 0.7
		
		# Add slight scale variation
		scale_factor *= _rng.randf_range(0.9, 1.1)
		
		# Add to pattern
		pattern.add_fragment(
			i,
			position,
			velocity,
			rotation,
			result_size,
			scale_factor
		)
	
	return pattern

# Get a suitable pattern for an asteroid based on its size and variant
func get_pattern_for_asteroid(patterns: Array, asteroid_size_category: int, variant_id: int) -> FragmentPatternData:
	# Convert size category to string
	var size_string = "medium"
	match asteroid_size_category:
		AsteroidData.SizeCategory.SMALL:
			return null  # Small asteroids don't fragment
		AsteroidData.SizeCategory.LARGE:
			size_string = "large"
	
	# Filter patterns for this size
	var matching_patterns = []
	for pattern in patterns:
		if pattern.source_size == size_string:
			matching_patterns.append(pattern)
	
	# If no matching patterns, return null
	if matching_patterns.is_empty():
		return null
	
	# Select pattern based on variant
	var index = variant_id % matching_patterns.size()
	return matching_patterns[index]
