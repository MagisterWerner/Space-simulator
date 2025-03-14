extends EntityData
class_name PlanetData

# Planet generation enums (copied from PlanetGeneratorBase for independence)
enum PlanetCategory { TERRAN, GASEOUS }
enum PlanetTheme {
	# Terran planets
	ARID, ICE, LAVA, LUSH, DESERT, ALPINE, OCEAN,
	# Gaseous planets
	JUPITER, SATURN, URANUS, NEPTUNE
}

# Planet properties
var planet_theme: int = 0
var planet_category: int = PlanetCategory.TERRAN
var is_gaseous: bool = false
var pixel_size: int = 256
var planet_name: String = ""

# Visual data - could be saved or generated at runtime
var texture_seed: int = 0
var atmosphere_data: Dictionary = {}

# Moons orbiting this planet
var moons: Array = []

func _init(p_entity_id: int = 0, p_position: Vector2 = Vector2.ZERO, p_seed: int = 0, p_theme: int = -1) -> void:
	super._init(p_entity_id, "planet", p_position, p_seed)
	
	if p_theme >= 0:
		planet_theme = p_theme
		is_gaseous = p_theme >= PlanetTheme.JUPITER
		planet_category = PlanetCategory.GASEOUS if is_gaseous else PlanetCategory.TERRAN
	
	texture_seed = p_seed

func add_moon(moon_data: MoonData) -> void:
	moons.append(moon_data)

# Get theme name based on ID
func get_theme_name() -> String:
	match planet_theme:
		PlanetTheme.ARID: return "Arid"
		PlanetTheme.ICE: return "Ice"
		PlanetTheme.LAVA: return "Lava"
		PlanetTheme.LUSH: return "Lush"
		PlanetTheme.DESERT: return "Desert"
		PlanetTheme.ALPINE: return "Alpine"
		PlanetTheme.OCEAN: return "Ocean"
		PlanetTheme.JUPITER: return "Jupiter-like"
		PlanetTheme.SATURN: return "Saturn-like"
		PlanetTheme.URANUS: return "Uranus-like"
		PlanetTheme.NEPTUNE: return "Neptune-like"
		_: return "Unknown"

# Generate a default name based on theme and seed
func generate_name() -> String:
	if planet_name.is_empty():
		planet_name = "%s-%d" % [get_theme_name(), seed_value % 1000]
	return planet_name

# Override duplicate to handle moon array
func duplicate() -> PlanetData:
	var copy = super.duplicate() as PlanetData
	copy.planet_theme = planet_theme
	copy.planet_category = planet_category
	copy.is_gaseous = is_gaseous
	copy.pixel_size = pixel_size
	copy.planet_name = planet_name
	copy.texture_seed = texture_seed
	copy.atmosphere_data = atmosphere_data.duplicate(true)
	
	# Duplicate moons
	copy.moons = []
	for moon in moons:
		copy.moons.append(moon.duplicate())
	
	return copy

# Serialization helper
func to_dict() -> Dictionary:
	var base_dict = super.to_dict()
	
	var planet_dict = {
		"planet_theme": planet_theme,
		"planet_category": planet_category,
		"is_gaseous": is_gaseous,
		"pixel_size": pixel_size,
		"planet_name": planet_name,
		"texture_seed": texture_seed,
		"atmosphere_data": atmosphere_data,
		"moons": []
	}
	
	# Serialize moons
	for moon in moons:
		planet_dict.moons.append(moon.to_dict())
	
	# Merge with base dictionary
	base_dict.merge(planet_dict, true)
	return base_dict

# Deserialization helper
static func from_dict(data: Dictionary) -> PlanetData:
	var base_data = EntityData.from_dict(data)
	
	var planet_data = PlanetData.new()
	planet_data.entity_id = base_data.entity_id
	planet_data.entity_type = base_data.entity_type
	planet_data.position = base_data.position
	planet_data.seed_value = base_data.seed_value
	planet_data.grid_cell = base_data.grid_cell
	planet_data.properties = base_data.properties
	
	# Planet-specific properties
	planet_data.planet_theme = data.get("planet_theme", 0)
	planet_data.planet_category = data.get("planet_category", PlanetCategory.TERRAN)
	planet_data.is_gaseous = data.get("is_gaseous", false)
	planet_data.pixel_size = data.get("pixel_size", 256)
	planet_data.planet_name = data.get("planet_name", "")
	planet_data.texture_seed = data.get("texture_seed", planet_data.seed_value)
	planet_data.atmosphere_data = data.get("atmosphere_data", {})
	
	# Deserialize moons
	var moons_data = data.get("moons", [])
	for moon_dict in moons_data:
		var moon = MoonData.from_dict(moon_dict)
		planet_data.moons.append(moon)
	
	return planet_data
