extends Resource
class_name FragmentPatternData

# Pattern identification
var pattern_id: int = 0
var source_size: String = "medium"  # The size of asteroid this pattern is for
var fragment_count: int = 2

# Pattern data arrays
var positions: Array[Vector2] = []
var velocities: Array[Vector2] = []
var rotations: Array[float] = []
var sizes: Array[String] = []
var scale_factors: Array[float] = []

# Create a complete pattern
func _init(p_pattern_id: int = 0, p_source_size: String = "medium", p_fragment_count: int = 2) -> void:
	pattern_id = p_pattern_id
	source_size = p_source_size
	fragment_count = p_fragment_count
	
	# Initialize arrays with proper size
	positions.resize(fragment_count)
	velocities.resize(fragment_count)
	rotations.resize(fragment_count)
	sizes.resize(fragment_count)
	scale_factors.resize(fragment_count)

# Add a fragment to the pattern
func add_fragment(index: int, position: Vector2, velocity: Vector2, rotation: float, size: String, scale: float) -> void:
	if index >= 0 and index < fragment_count:
		positions[index] = position
		velocities[index] = velocity
		rotations[index] = rotation
		sizes[index] = size
		scale_factors[index] = scale

# Override duplicate to ensure proper copying
func duplicate(subresources: bool = false) -> Resource:
	var copy = get_script().new(pattern_id, source_size, fragment_count)
	
	# Copy the arrays
	for i in range(fragment_count):
		if i < positions.size():
			copy.positions[i] = positions[i]
		if i < velocities.size():
			copy.velocities[i] = velocities[i]
		if i < rotations.size():
			copy.rotations[i] = rotations[i]
		if i < sizes.size():
			copy.sizes[i] = sizes[i]
		if i < scale_factors.size():
			copy.scale_factors[i] = scale_factors[i]
			
	return copy

# Generate a deterministic fragment pattern for an asteroid size
static func generate_for_size(seed_value: int, source_size: String, pattern_id: int) -> FragmentPatternData:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value + pattern_id
	
	var fragment_count = 0
	var result_sizes = []
	
	# Determine fragment count and sizes based on source size
	match source_size:
		"large":
			fragment_count = 2
			result_sizes = ["medium", "small"]
		"medium":
			fragment_count = 2
			result_sizes = ["small", "small"]
		"small":
			# Small asteroids don't generate fragments
			fragment_count = 0
			return null
		_:
			# Default to medium behavior
			fragment_count = 2
			result_sizes = ["small", "small"]
	
	if fragment_count == 0:
		return null
	
	# Create pattern
	var pattern = FragmentPatternData.new(pattern_id, source_size, fragment_count)
	
	# Calculate base explosion force
	var base_force = 50.0
	
	# Generate fragments with variations
	for i in range(fragment_count):
		# Vary position
		var angle = (TAU / fragment_count) * i + rng.randf_range(-0.3, 0.3)
		var distance = rng.randf_range(10, 30)
		var position = Vector2(cos(angle), sin(angle)) * distance
		
		# Vary velocity
		var explosion_dir = Vector2(cos(angle), sin(angle))
		var explosion_speed = rng.randf_range(base_force * 0.8, base_force * 1.2)
		var velocity = explosion_dir * explosion_speed
		
		# Rotation and scale
		var rotation = rng.randf_range(-1.5, 1.5)
		
		var scale_factor = 0.6
		if result_sizes[i] == "medium":
			scale_factor = 0.7
		
		# Add slight scale variation
		scale_factor *= rng.randf_range(0.9, 1.1)
		
		# Add to pattern
		pattern.add_fragment(
			i,
			position,
			velocity,
			rotation,
			result_sizes[i],
			scale_factor
		)
	
	return pattern

# Generate a collection of pre-computed patterns
static func generate_pattern_collection(seed_value: int, pattern_count: int = 10) -> Array:
	var patterns = []
	
	# Generate patterns for different source sizes
	for source_size in ["large", "medium"]:
		for i in range(pattern_count):
			var pattern_id = i + (0 if source_size == "large" else pattern_count)
			var pattern = generate_for_size(seed_value, source_size, pattern_id)
			if pattern:
				patterns.append(pattern)
	
	return patterns

# Get a specific pattern for an asteroid size and variant
static func get_pattern_for_asteroid(patterns: Array, asteroid_size: String, variant_id: int) -> FragmentPatternData:
	# Filter patterns for this size
	var matching_patterns = []
	for pattern in patterns:
		if pattern.source_size == asteroid_size:
			matching_patterns.append(pattern)
	
	# If no matching patterns, return null
	if matching_patterns.is_empty():
		return null
	
	# Select pattern based on variant
	var index = variant_id % matching_patterns.size()
	return matching_patterns[index]

# Serialization helper
func to_dict() -> Dictionary:
	var result = {
		"pattern_id": pattern_id,
		"source_size": source_size,
		"fragment_count": fragment_count,
		"positions": [],
		"velocities": [],
		"rotations": [],
		"sizes": [],
		"scale_factors": []
	}
	
	# Serialize vectors
	for i in range(fragment_count):
		result.positions.append({"x": positions[i].x, "y": positions[i].y})
		result.velocities.append({"x": velocities[i].x, "y": velocities[i].y})
		result.rotations.append(rotations[i])
		result.sizes.append(sizes[i])
		result.scale_factors.append(scale_factors[i])
	
	return result

# Deserialization helper
static func from_dict(data: Dictionary) -> FragmentPatternData:
	var pattern = FragmentPatternData.new(
		data.get("pattern_id", 0),
		data.get("source_size", "medium"),
		data.get("fragment_count", 2)
	)
	
	var positions_data = data.get("positions", [])
	var velocities_data = data.get("velocities", [])
	var rotations_data = data.get("rotations", [])
	var sizes_data = data.get("sizes", [])
	var scale_factors_data = data.get("scale_factors", [])
	
	# Deserialize vectors
	for i in range(min(pattern.fragment_count, positions_data.size())):
		var pos = positions_data[i]
		var position = Vector2(pos.get("x", 0), pos.get("y", 0))
		
		var vel = velocities_data[i] if i < velocities_data.size() else {"x": 0, "y": 0}
		var velocity = Vector2(vel.get("x", 0), vel.get("y", 0))
		
		var rotation = rotations_data[i] if i < rotations_data.size() else 0.0
		var size = sizes_data[i] if i < sizes_data.size() else "small"
		var scale = scale_factors_data[i] if i < scale_factors_data.size() else 0.6
		
		pattern.add_fragment(i, position, velocity, rotation, size, scale)
	
	return pattern
