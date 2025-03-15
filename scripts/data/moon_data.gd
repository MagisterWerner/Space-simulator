extends EntityData
class_name MoonData

# Moon type enum (copied from MoonGenerator for independence)
enum MoonType {
	ROCKY,
	ICY,
	VOLCANIC
}

# Moon properties
var moon_type: int = MoonType.ROCKY
var moon_name: String = ""
var pixel_size: int = 32
var parent_planet_id: int = -1

# Orbit parameters
var distance: float = 0.0
var base_angle: float = 0.0
var orbit_speed: float = 0.0
var orbit_deviation: float = 0.0
var phase_offset: float = 0.0
var orbital_inclination: float = 1.0
var orbit_vertical_offset: float = 0.0

# Visual parameters
var is_gaseous: bool = false
var orbit_color: Color = Color.WHITE
var indicator_color: Color = Color.WHITE
var orbit_indicator_size: float = 4.0

func _init(p_entity_id: int = 0, p_position: Vector2 = Vector2.ZERO, p_seed: int = 0, p_type: int = MoonType.ROCKY) -> void:
	super._init(p_entity_id, "moon", p_position, p_seed)
	moon_type = p_type
	
	# Set default orbit colors based on type
	match moon_type:
		MoonType.ROCKY:
			orbit_color = Color(0.7, 0.7, 0.7, 0.5)
			indicator_color = Color(0.8, 0.8, 0.8, 0.8)
		MoonType.ICY:
			orbit_color = Color(0.5, 0.8, 1.0, 0.5)
			indicator_color = Color(0.6, 0.9, 1.0, 0.8)
		MoonType.VOLCANIC:
			orbit_color = Color(1.0, 0.3, 0.0, 0.5)
			indicator_color = Color(1.0, 0.3, 0.0, 0.8)

# Get type prefix based on moon type
func get_type_prefix() -> String:
	match moon_type:
		MoonType.ROCKY: return "Rocky"
		MoonType.ICY: return "Icy"
		MoonType.VOLCANIC: return "Volcanic"
		_: return "Moon"

# Generate a default name based on type and seed
func generate_name() -> String:
	if moon_name.is_empty():
		moon_name = "%s Moon-%d" % [get_type_prefix(), seed_value % 1000]
	return moon_name

# Create a deep copy - custom method that doesn't override native methods
func clone() -> MoonData:
	var copy = super.clone() as MoonData
	copy.moon_type = moon_type
	copy.moon_name = moon_name
	copy.pixel_size = pixel_size
	copy.parent_planet_id = parent_planet_id
	
	# Orbit parameters
	copy.distance = distance
	copy.base_angle = base_angle
	copy.orbit_speed = orbit_speed
	copy.orbit_deviation = orbit_deviation
	copy.phase_offset = phase_offset
	copy.orbital_inclination = orbital_inclination
	copy.orbit_vertical_offset = orbit_vertical_offset
	
	# Visual parameters
	copy.is_gaseous = is_gaseous
	copy.orbit_color = orbit_color
	copy.indicator_color = indicator_color
	copy.orbit_indicator_size = orbit_indicator_size
	
	return copy

# Serialization helper
func to_dict() -> Dictionary:
	var base_dict = super.to_dict()
	
	var moon_dict = {
		"moon_type": moon_type,
		"moon_name": moon_name,
		"pixel_size": pixel_size,
		"parent_planet_id": parent_planet_id,
		"distance": distance,
		"base_angle": base_angle,
		"orbit_speed": orbit_speed,
		"orbit_deviation": orbit_deviation,
		"phase_offset": phase_offset,
		"orbital_inclination": orbital_inclination,
		"orbit_vertical_offset": orbit_vertical_offset,
		"is_gaseous": is_gaseous,
		"orbit_color": {
			"r": orbit_color.r,
			"g": orbit_color.g,
			"b": orbit_color.b,
			"a": orbit_color.a
		},
		"indicator_color": {
			"r": indicator_color.r,
			"g": indicator_color.g,
			"b": indicator_color.b,
			"a": indicator_color.a
		},
		"orbit_indicator_size": orbit_indicator_size
	}
	
	# Merge with base dictionary
	base_dict.merge(moon_dict, true)
	return base_dict

# Deserialization helper
static func from_dict(data: Dictionary) -> MoonData:
	var base_data = EntityData.from_dict(data)
	
	var moon_data = MoonData.new()
	moon_data.entity_id = base_data.entity_id
	moon_data.entity_type = base_data.entity_type
	moon_data.position = base_data.position
	moon_data.seed_value = base_data.seed_value
	moon_data.grid_cell = base_data.grid_cell
	moon_data.properties = base_data.properties
	
	# Moon-specific properties
	moon_data.moon_type = data.get("moon_type", MoonType.ROCKY)
	moon_data.moon_name = data.get("moon_name", "")
	moon_data.pixel_size = data.get("pixel_size", 32)
	moon_data.parent_planet_id = data.get("parent_planet_id", -1)
	
	# Orbit parameters
	moon_data.distance = data.get("distance", 0.0)
	moon_data.base_angle = data.get("base_angle", 0.0)
	moon_data.orbit_speed = data.get("orbit_speed", 0.0)
	moon_data.orbit_deviation = data.get("orbit_deviation", 0.0)
	moon_data.phase_offset = data.get("phase_offset", 0.0)
	moon_data.orbital_inclination = data.get("orbital_inclination", 1.0)
	moon_data.orbit_vertical_offset = data.get("orbit_vertical_offset", 0.0)
	
	# Visual parameters
	moon_data.is_gaseous = data.get("is_gaseous", false)
	
	# Colors
	var orbit_color_dict = data.get("orbit_color", {"r": 1.0, "g": 1.0, "b": 1.0, "a": 0.5})
	moon_data.orbit_color = Color(
		orbit_color_dict.get("r", 1.0),
		orbit_color_dict.get("g", 1.0),
		orbit_color_dict.get("b", 1.0),
		orbit_color_dict.get("a", 0.5)
	)
	
	var indicator_color_dict = data.get("indicator_color", {"r": 1.0, "g": 1.0, "b": 1.0, "a": 0.8})
	moon_data.indicator_color = Color(
		indicator_color_dict.get("r", 1.0),
		indicator_color_dict.get("g", 1.0),
		indicator_color_dict.get("b", 1.0),
		indicator_color_dict.get("a", 0.8)
	)
	
	moon_data.orbit_indicator_size = data.get("orbit_indicator_size", 4.0)
	
	return moon_data
