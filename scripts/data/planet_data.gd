extends EntityData
class_name PlanetData

# Planet category - based on PlanetGeneratorBase's enum
enum PlanetCategory { TERRAN, GASEOUS }

# Planet theme - based on PlanetGeneratorBase's enum
enum PlanetTheme {
	# Terran planets
	ARID, ICE, LAVA, LUSH, DESERT, ALPINE, OCEAN,
	# Gaseous planets
	JUPITER, SATURN, URANUS, NEPTUNE
}

# Planet type and themes
var planet_category: int = PlanetCategory.TERRAN
var planet_theme: int = PlanetTheme.ARID

# Planet size in pixels
var pixel_size: int = 256

# Planet features
var has_atmosphere: bool = true
var atmosphere_data: Dictionary = {}
var is_player_starting_planet: bool = false

# Moon system
var moon_count: int = 0
var moons: Array[MoonData] = []

# Trade and resources data
var resource_multipliers: Dictionary = {}
var resource_availability: Dictionary = {}

# Override to implement a deeper copy
func duplicate() -> PlanetData:
	var copy = super.duplicate() as PlanetData
	copy.planet_category = planet_category
	copy.planet_theme = planet_theme
	copy.pixel_size = pixel_size
	copy.has_atmosphere = has_atmosphere
	copy.atmosphere_data = atmosphere_data.duplicate()
	copy.is_player_starting_planet = is_player_starting_planet
	copy.moon_count = moon_count
	
	# Deep copy moons array
	copy.moons = []
	for moon in moons:
		copy.moons.append(moon.duplicate())
	
	# Deep copy resource data
	copy.resource_multipliers = resource_multipliers.duplicate()
	copy.resource_availability = resource_availability.duplicate()
	
	return copy

func get_theme_name() -> String:
	# Return human-readable theme name
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

func get_category_name() -> String:
	return "Terran" if planet_category == PlanetCategory.TERRAN else "Gaseous"

func is_gaseous() -> bool:
	return planet_category == PlanetCategory.GASEOUS

func is_terran() -> bool:
	return planet_category == PlanetCategory.TERRAN
