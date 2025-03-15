extends Resource
class_name FragmentPatternData

# Core properties
var pattern_id: int = 0
var pattern_seed: int = 0
var source_entity_id: int = -1  # ID of the entity that created this pattern
var source_position: Vector2 = Vector2.ZERO
var source_velocity: Vector2 = Vector2.ZERO
var source_size_category: String = "medium"

# Fragment properties
var fragment_count: int = 0
var fragments: Array[Dictionary] = []  # Array of fragment definitions

# Optional pattern properties
var explosion_force: float = 1.0
var spread_angle: float = TAU  # Default is full 360 degrees
var directional_bias: Vector2 = Vector2.ZERO  # Can bias fragments in a direction

func _init() -> void:
	# Initialize with current timestamp for debugging
	pattern_id = Time.get_ticks_msec()

# Add a fragment to the pattern
func add_fragment(position_offset: Vector2, velocity: Vector2, size_factor: float, size_category: String = "") -> void:
	fragments.append({
		"position_offset": position_offset,
		"velocity": velocity,
		"size_factor": size_factor,
		"size_category": size_category if size_category else source_size_category
	})
	fragment_count = fragments.size()

# Add multiple fragments at once
func add_fragments(fragment_array: Array[Dictionary]) -> void:
	fragments.append_array(fragment_array)
	fragment_count = fragments.size()

# Generate positions for fragments arranged in a circle pattern
func generate_circular_pattern(count: int, min_distance: float, max_distance: float) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = pattern_seed
	
	# Clear existing fragments
	fragments.clear()
	
	for i in range(count):
		# Calculate angle with some randomization
		var angle = (TAU / count) * i + rng.randf_range(-0.3, 0.3)
		
		# Calculate distance
		var distance = rng.randf_range(min_distance, max_distance)
		
		# Create position offset and velocity
		var pos_offset = Vector2(cos(angle), sin(angle)) * distance
		var velocity = Vector2(cos(angle), sin(angle)) * rng.randf_range(30.0, 60.0)
		
		# Determine size - first fragment of large asteroid is medium
		var size_category = "small"
		var size_factor = 0.6
		
		if source_size_category == "large" and i == 0:
			size_category = "medium"
			size_factor = 0.7
		
		# Add the fragment
		add_fragment(pos_offset, velocity, size_factor, size_category)
	
	fragment_count = fragments.size()

# Clone this pattern
func duplicate() -> FragmentPatternData:
	var copy = get_script().new()
	copy.pattern_id = pattern_id
	copy.pattern_seed = pattern_seed
	copy.source_entity_id = source_entity_id
	copy.source_position = source_position
	copy.source_velocity = source_velocity
	copy.source_size_category = source_size_category
	copy.fragment_count = fragment_count
	copy.explosion_force = explosion_force
	copy.spread_angle = spread_angle
	copy.directional_bias = directional_bias
	
	# Deep copy fragments array
	copy.fragments = []
	for fragment in fragments:
		copy.fragments.append(fragment.duplicate())
	
	return copy
