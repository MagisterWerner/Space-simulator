extends EntityData
class_name MoonData

# Moon type - based on MoonGenerator's enum
enum MoonType { ROCKY, ICY, VOLCANIC }

# Moon base properties
var moon_type: int = MoonType.ROCKY
var pixel_size: int = 32
var parent_planet_id: int = -1

# Orbital parameters
var orbit_distance: float = 0.0
var orbit_speed: float = 0.0
var orbit_deviation: float = 0.0
var base_angle: float = 0.0
var phase_offset: float = 0.0
var orbital_inclination: float = 1.0
var orbit_vertical_offset: float = 0.0

# Visual parameters
var orbit_color: Color = Color.WHITE
var is_gaseous: bool = false

func _init() -> void:
	super._init()
	entity_type = "moon"

# Override clone to implement a deeper copy
func clone() -> MoonData:
	var copy = super.clone() as MoonData
	copy.moon_type = moon_type
	copy.pixel_size = pixel_size
	copy.parent_planet_id = parent_planet_id
	copy.orbit_distance = orbit_distance
	copy.orbit_speed = orbit_speed
	copy.orbit_deviation = orbit_deviation
	copy.base_angle = base_angle
	copy.phase_offset = phase_offset
	copy.orbital_inclination = orbital_inclination
	copy.orbit_vertical_offset = orbit_vertical_offset
	copy.orbit_color = orbit_color
	copy.is_gaseous = is_gaseous
	return copy

func get_type_name() -> String:
	match moon_type:
		MoonType.ROCKY: return "Rocky"
		MoonType.ICY: return "Icy"
		MoonType.VOLCANIC: return "Volcanic"
		_: return "Unknown"
