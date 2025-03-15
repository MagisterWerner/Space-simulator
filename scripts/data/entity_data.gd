extends Resource
class_name EntityData

# Core entity identification
var entity_id: int = 0
var seed_value: int = 0
var grid_cell: Vector2i = Vector2i(-1, -1)
var world_position: Vector2 = Vector2.ZERO
var entity_type: String = ""

# Common entity properties
var entity_name: String = ""
var entity_scale: float = 1.0

# Optional metadata for specialized processing
var metadata: Dictionary = {}

# Debug info - helps with debugging generation issues
var creation_timestamp: int = 0

func _init() -> void:
	# Set creation timestamp for debugging
	creation_timestamp = Time.get_ticks_msec()

# Clone/deep copy function
func duplicate() -> EntityData:
	var copy = get_script().new()
	copy.entity_id = entity_id
	copy.seed_value = seed_value
	copy.grid_cell = grid_cell
	copy.world_position = world_position
	copy.entity_type = entity_type
	copy.entity_name = entity_name
	copy.entity_scale = entity_scale
	copy.metadata = metadata.duplicate(true)
	copy.creation_timestamp = creation_timestamp
	return copy

func to_string() -> String:
	return "EntityData[id=%d, type=%s, pos=%s, cell=%s]" % [
		entity_id,
		entity_type,
		str(world_position),
		str(grid_cell)
	]
