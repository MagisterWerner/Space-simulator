extends Resource
class_name EntityData

# Core entity properties
var entity_id: int = 0
var entity_type: String = ""
var position: Vector2 = Vector2.ZERO
var seed_value: int = 0
var grid_cell: Vector2i = Vector2i(-1, -1)

# Additional properties - flexible dictionary for type-specific data
var properties: Dictionary = {}

func _init(p_entity_id: int = 0, p_type: String = "", p_position: Vector2 = Vector2.ZERO, p_seed: int = 0, p_grid_cell: Vector2i = Vector2i(-1, -1)) -> void:
	entity_id = p_entity_id
	entity_type = p_type
	position = p_position
	seed_value = p_seed
	grid_cell = p_grid_cell

# Get a property with optional default value
func get_property(key: String, default_value = null):
	if properties.has(key):
		return properties[key]
	return default_value

# Set a property value
func set_property(key: String, value) -> void:
	properties[key] = value

# Create a deep copy of this data - custom method that doesn't override native methods
func clone() -> EntityData:
	var copy = get_script().new()
	copy.entity_id = entity_id
	copy.entity_type = entity_type
	copy.position = position
	copy.seed_value = seed_value
	copy.grid_cell = grid_cell
	copy.properties = properties.duplicate()
	return copy

# Serialization helper method
func to_dict() -> Dictionary:
	return {
		"entity_id": entity_id,
		"entity_type": entity_type,
		"position": {"x": position.x, "y": position.y},
		"seed_value": seed_value,
		"grid_cell": {"x": grid_cell.x, "y": grid_cell.y},
		"properties": properties
	}

# Deserialization helper method
static func from_dict(data: Dictionary) -> EntityData:
	var entity_data = EntityData.new()
	entity_data.entity_id = data.get("entity_id", 0)
	entity_data.entity_type = data.get("entity_type", "")
	
	var pos = data.get("position", {"x": 0, "y": 0})
	entity_data.position = Vector2(pos.get("x", 0), pos.get("y", 0))
	
	entity_data.seed_value = data.get("seed_value", 0)
	
	var cell = data.get("grid_cell", {"x": -1, "y": -1})
	entity_data.grid_cell = Vector2i(cell.get("x", -1), cell.get("y", -1))
	
	entity_data.properties = data.get("properties", {})
	
	return entity_data
