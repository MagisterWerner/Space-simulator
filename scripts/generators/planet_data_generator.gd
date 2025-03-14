extends RefCounted
class_name PlanetDataGenerator

# Copy of planet enums for easy direct access
enum PlanetCategory { TERRAN, GASEOUS }
enum PlanetTheme {
	# Terran planets
	ARID, ICE, LAVA, LUSH, DESERT, ALPINE, OCEAN,
	# Gaseous planets
	JUPITER, SATURN, URANUS, NEPTUNE
}

# Moon type enum
enum MoonType {
	ROCKY,
	ICY,
	VOLCANIC
}

# Planet generation constants
const TERRAN_PLANET_SIZES = [256, 272, 288]
const GASEOUS_PLANET_SIZES = [512, 544, 576]

# Moon generation constants
const MIN_MOONS_TERRAN = 0
const MAX_MOONS_TERRAN = 2
const MIN_MOONS_GASEOUS = 2
const MAX_MOONS_GASEOUS = 5
const MOON_DISTANCE_MIN = 1.6  # Multiplier of planet radius
const MOON_DISTANCE_MAX = 3.0  # Multiplier of planet radius
const MOON_ORBIT_SPEED_MIN = 0.02
const MOON_ORBIT_SPEED_MAX = 0.1

# Moon type probabilities by planet theme
const MOON_TYPE_PROBABILITIES = {
	# Terran planets
	PlanetTheme.ARID: {"rocky": 0.8, "icy": 0.1, "volcanic": 0.1},
	PlanetTheme.ICE: {"rocky": 0.2, "icy": 0.7, "volcanic": 0.1},
	PlanetTheme.LAVA: {"rocky": 0.3, "icy": 0.0, "volcanic": 0.7},
	PlanetTheme.LUSH: {"rocky": 0.6, "icy": 0.3, "volcanic": 0.1},
	PlanetTheme.DESERT: {"rocky": 0.9, "icy": 0.0, "volcanic": 0.1},
	PlanetTheme.ALPINE: {"rocky": 0.5, "icy": 0.5, "volcanic": 0.0},
	PlanetTheme.OCEAN: {"rocky": 0.4, "icy": 0.5, "volcanic": 0.1},
	
	# Gaseous planets
	PlanetTheme.JUPITER: {"rocky": 0.5, "icy": 0.3, "volcanic": 0.2},
	PlanetTheme.SATURN: {"rocky": 0.6, "icy": 0.3, "volcanic": 0.1},
	PlanetTheme.URANUS: {"rocky": 0.2, "icy": 0.7, "volcanic": 0.1},
	PlanetTheme.NEPTUNE: {"rocky": 0.3, "icy": 0.6, "volcanic": 0.1}
}

# Internal state
var _seed_value: int = 0
var _rng: RandomNumberGenerator
var _moon_generator: MoonDataGenerator

# Initialize with a seed
func _init(seed_value: int = 0):
	_seed_value = seed_value
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value
	_moon_generator = MoonDataGenerator.new(seed_value)

# Generate a planet with the given parameters
func generate_planet(entity_id: int, position: Vector2, seed_value: int, theme_id: int = -1, is_player_starting: bool = false) -> PlanetData:
	# Use a consistent seed for deterministic generation
	var planet_seed = seed_value
	_rng.seed = planet_seed
	
	# Determine planet theme if not explicitly specified
	if theme_id < 0:
		theme_id = _rng.randi() % PlanetTheme.size()
	
	# Determine if the planet is gaseous
	var is_gaseous = theme_id >= PlanetTheme.JUPITER
	var planet_category = PlanetCategory.GASEOUS if is_gaseous else PlanetCategory.TERRAN
	
	# Create planet data
	var planet_data = PlanetData.new(
		entity_id,
		position,
		planet_seed,
		theme_id
	)
	
	# Generate planet size
	planet_data.pixel_size = _generate_planet_size(is_gaseous, planet_seed)
	
	# Generate planet name
	planet_data.planet_name = _generate_planet_name(theme_id, planet_seed)
	
	# Generate atmosphere data
	planet_data.atmosphere_data = _generate_atmosphere_data(theme_id, planet_seed)
	
	# Generate moons for this planet
	var moon_count = _determine_moon_count(planet_data)
	
	for i in range(moon_count):
		var moon_id = entity_id * 100 + i + 1
		var moon_seed = planet_seed + 10000 + i * 100
		var moon_data = _generate_moon(moon_id, planet_data, moon_seed, i)
		planet_data.add_moon(moon_data)
	
	return planet_data

# Generate a name for the planet
func _generate_planet_name(theme_id: int, seed_value: int) -> String:
	_rng.seed = seed_value + 12345
	
	# Theme-based prefixes
	var theme_prefixes = {
		PlanetTheme.ARID: ["Dune", "Arrakis", "Dust", "Sand", "Dry", "Barren"],
		PlanetTheme.ICE: ["Frost", "Glacier", "Cryo", "Rime", "Hoth", "Freeze"],
		PlanetTheme.LAVA: ["Ember", "Magma", "Ash", "Char", "Flame", "Cinder"],
		PlanetTheme.LUSH: ["Green", "Eden", "Bloom", "Verdant", "Flora", "Haven"],
		PlanetTheme.DESERT: ["Waste", "Arid", "Parched", "Sear", "Desiccate", "Xeric"],
		PlanetTheme.ALPINE: ["Peak", "Mount", "Ridge", "Alp", "Crag", "Highland"],
		PlanetTheme.OCEAN: ["Deep", "Aqua", "Hydro", "Tide", "Wave", "Oceanus"],
		PlanetTheme.JUPITER: ["Giant", "Storm", "Tempest", "Cloud", "Cyclone", "Jove"],
		PlanetTheme.SATURN: ["Ring", "Band", "Circlet", "Halo", "Disc", "Crown"],
		PlanetTheme.URANUS: ["Sky", "Cerulean", "Azure", "Cyan", "Cobalt", "Zephyr"],
		PlanetTheme.NEPTUNE: ["Dark", "Sapphire", "Abyssal", "Ultramarine", "Navy", "Poseidon"]
	}
	
	var suffixes = ["Prime", "Major", "Minor", "Alpha", "Beta", "Proxima", "Nova", "Secundus"]
	
	# Get appropriate prefix list
	var prefixes = theme_prefixes.get(theme_id, ["Planet"])
	
	# Generate name components
	var prefix = prefixes[_rng.randi() % prefixes.size()]
	var designation = str(_rng.randi_range(1, 999))
	var use_suffix = _rng.randf() < 0.3
	var suffix = ""
	
	if use_suffix:
		suffix = " " + suffixes[_rng.randi() % suffixes.size()]
	
	return prefix + "-" + designation + suffix

# Generate atmosphere data
func _generate_atmosphere_data(theme_id: int, seed_value: int) -> Dictionary:
	_rng.seed = seed_value + 55555
	
	# Base colors for each theme
	var base_colors = {
		PlanetTheme.ARID: Color(0.8, 0.6, 0.4, 0.35),
		PlanetTheme.ICE: Color(0.8, 0.9, 1.0, 0.3),
		PlanetTheme.LAVA: Color(0.9, 0.3, 0.1, 0.5),
		PlanetTheme.LUSH: Color(0.5, 0.8, 1.0, 0.4),
		PlanetTheme.DESERT: Color(0.9, 0.7, 0.4, 0.45),
		PlanetTheme.ALPINE: Color(0.7, 0.9, 1.0, 0.35),
		PlanetTheme.OCEAN: Color(0.4, 0.7, 0.9, 0.4),
		PlanetTheme.JUPITER: Color(0.75, 0.70, 0.55, 0.3),
		PlanetTheme.SATURN: Color(0.80, 0.78, 0.60, 0.3),
		PlanetTheme.URANUS: Color(0.65, 0.85, 0.80, 0.3),
		PlanetTheme.NEPTUNE: Color(0.50, 0.65, 0.75, 0.3)
	}
	
	var base_color = base_colors.get(theme_id, Color(0.5, 0.7, 0.9, 0.4))
	var thickness = 0.8 # Base thickness
	
	# Apply random variations
	var color_variation = 0.1
	var r = clamp(base_color.r + (_rng.randf() - 0.5) * color_variation, 0, 1)
	var g = clamp(base_color.g + (_rng.randf() - 0.5) * color_variation, 0, 1)
	var b = clamp(base_color.b + (_rng.randf() - 0.5) * color_variation, 0, 1)
	var a = clamp(base_color.a + (_rng.randf() - 0.5) * color_variation * 0.5, 0.15, 0.85)
	
	var color = Color(r, g, b, a)
	thickness *= (1.0 + (_rng.randf() - 0.5) * 0.1)
	
	# Adjust for gaseous planets
	if theme_id >= PlanetTheme.JUPITER:
		color.a = clamp(color.a, 0.25, 0.35)
	
	return {
		"color": color,
		"thickness": thickness,
		"category": PlanetCategory.GASEOUS if theme_id >= PlanetTheme.JUPITER else PlanetCategory.TERRAN
	}

# Generate a moon for a planet
func _generate_moon(moon_id: int, parent_planet: PlanetData, seed_value: int, index: int) -> MoonData:
	_rng.seed = seed_value
	
	# Determine moon type
	var moon_type = _determine_moon_type(parent_planet.planet_theme)
	
	# Generate moon data
	var position = parent_planet.position # Initial position same as planet
	var moon_data = _moon_generator.generate_moon(moon_id, position, seed_value, moon_type)
	
	# Set parent planet ID
	moon_data.parent_planet_id = parent_planet.entity_id
	
	# Determine orbit parameters
	_configure_moon_orbit(moon_data, parent_planet, index)
	
	return moon_data

# Configure moon orbit around a planet
func _configure_moon_orbit(moon_data: MoonData, planet_data: PlanetData, index: int) -> void:
	var planet_radius = planet_data.pixel_size / 2.0
	var seed_offset = 789 + index * 123
	_rng.seed = _seed_value + seed_offset
	
	# Base distance multiplier based on planet type and moon index
	var min_distance_multiplier = MOON_DISTANCE_MIN
	var max_distance_multiplier = MOON_DISTANCE_MAX
	
	# Larger planets have more distant moons
	if planet_data.is_gaseous:
		min_distance_multiplier += 0.1 * index
		max_distance_multiplier += 0.2 * index
	else:
		min_distance_multiplier += 0.2 * index
		max_distance_multiplier += 0.3 * index
	
	# Calculate orbit parameters
	var distance = _rng.randf_range(min_distance_multiplier, max_distance_multiplier) * planet_radius
	var base_angle = _rng.randf() * TAU  # Random starting angle
	var orbit_speed = _rng.randf_range(MOON_ORBIT_SPEED_MIN, MOON_ORBIT_SPEED_MAX)
	
	# Reduce orbit speed for more distant moons
	orbit_speed *= 1.0 / (1.0 + 0.2 * index)
	
	# Calculate orbit deviations and inclination
	var orbit_deviation = _rng.randf_range(0.0, 0.1)  # Slight eccentricity
	var orbital_inclination = _rng.randf_range(0.8, 1.2)  # Vertical stretching
	
	# Apply more dramatic inclination for some moons
	if _rng.randf() < 0.2:
		orbital_inclination = _rng.randf_range(0.5, 2.0)
	
	var phase_offset = _rng.randf() * TAU  # Phase offset for animation variation
	var orbit_vertical_offset = _rng.randf_range(-10.0, 10.0)  # Slight vertical shifting
	
	# Apply parameters to moon
	moon_data.distance = distance
	moon_data.base_angle = base_angle
	moon_data.orbit_speed = orbit_speed
	moon_data.orbit_deviation = orbit_deviation
	moon_data.phase_offset = phase_offset
	moon_data.orbital_inclination = orbital_inclination
	moon_data.orbit_vertical_offset = orbit_vertical_offset

# Helper functions

# Generate a planet size based on type
func _generate_planet_size(is_gaseous: bool, seed_value: int) -> int:
	_rng.seed = seed_value + 9876
	
	# Choose from appropriate size range
	var size_array = GASEOUS_PLANET_SIZES if is_gaseous else TERRAN_PLANET_SIZES
	var index = _rng.randi() % size_array.size()
	return size_array[index]

# Determine number of moons for a planet
func _determine_moon_count(planet_data: PlanetData) -> int:
	_rng.seed = planet_data.seed_value + 54321
	
	if planet_data.is_gaseous:
		return _rng.randi_range(MIN_MOONS_GASEOUS, MAX_MOONS_GASEOUS)
	else:
		return _rng.randi_range(MIN_MOONS_TERRAN, MAX_MOONS_TERRAN)

# Determine moon type based on planet theme
func _determine_moon_type(planet_theme: int) -> int:
	# Get probabilities for this planet type
	var probabilities = MOON_TYPE_PROBABILITIES.get(planet_theme, {"rocky": 0.6, "icy": 0.2, "volcanic": 0.2})
	
	# Generate random value
	var rand_val = _rng.randf()
	
	# Determine type based on probabilities
	if rand_val < probabilities.rocky:
		return MoonType.ROCKY
	elif rand_val < probabilities.rocky + probabilities.icy:
		return MoonType.ICY
	else:
		return MoonType.VOLCANIC

# Static helpers

# Get planet theme name
static func get_theme_name(theme_id: int) -> String:
	match theme_id:
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

# Get planet category from theme
static func get_planet_category(theme_id: int) -> int:
	return PlanetCategory.GASEOUS if theme_id >= PlanetTheme.JUPITER else PlanetCategory.TERRAN
