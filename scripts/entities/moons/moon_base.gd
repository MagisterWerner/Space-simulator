# scripts/entities/moons/moon_base.gd
extends Node2D
class_name MoonBase

enum MoonType { ROCKY, ICY, VOLCANIC }

# Common properties for all moons
var seed_value: int = 0
var pixel_size: int = 32
var moon_texture: Texture2D
var parent_planet = null
var distance: float = 0
var base_angle: float = 0
var orbit_speed: float = 0
var orbit_deviation: float = 0
var phase_offset: float = 0
var moon_name: String
var use_texture_cache: bool = true
var is_gaseous: bool = false
var moon_type: int = MoonType.ROCKY  # Default type
var entity_id: int = 0

# Visual indicator properties
var orbit_color: Color = Color(1, 1, 1, 0.5)
var indicator_color: Color = Color(1, 1, 1, 0.8)
var orbit_indicator_size: float = 4.0

# Orbital parameters
var orbital_inclination: float = 1.0
var orbit_vertical_offset: float = 0.0

# Reference to initialization parameters
var _init_params: Dictionary = {}

# Type-specific properties mapped by moon type
const TYPE_PROPERTIES = {
	MoonType.VOLCANIC: {
		"prefix": "Volcanic",
		"orbit_color": Color(1.0, 0.3, 0.0, 0.5),
		"indicator_color": Color(1.0, 0.3, 0.0, 0.8),
		"cache_offset": 2
	},
	MoonType.ROCKY: {
		"prefix": "Rocky",
		"orbit_color": Color(0.7, 0.7, 0.7, 0.5),
		"indicator_color": Color(0.8, 0.8, 0.8, 0.8),
		"cache_offset": 0
	},
	MoonType.ICY: {
		"prefix": "Icy",
		"orbit_color": Color(0.5, 0.8, 1.0, 0.5),
		"indicator_color": Color(0.6, 0.9, 1.0, 0.8),
		"cache_offset": 1
	}
}

func _ready() -> void:
	# Set z-index and connect to seed manager
	z_index = -9
	
	if has_node("/root/SeedManager"):
		var seed_manager = get_node("/root/SeedManager")
		if not seed_manager.is_connected("seed_changed", _on_seed_changed):
			seed_manager.connect("seed_changed", _on_seed_changed)

func _process(_delta) -> void:
	queue_redraw()

func _draw() -> void:
	if moon_texture:
		# Draw moon texture centered
		draw_texture(moon_texture, -Vector2(pixel_size, pixel_size) / 2, Color.WHITE)
		
		# Debug indicator
		if parent_planet and parent_planet.debug_draw_orbits:
			var type_props = TYPE_PROPERTIES.get(moon_type, TYPE_PROPERTIES[MoonType.ROCKY])
			draw_circle(Vector2.ZERO, orbit_indicator_size, type_props.indicator_color)

func _on_seed_changed(_new_seed: int) -> void:
	if _init_params.is_empty():
		return
	
	# Update seed with new base but preserve unique part
	if has_node("/root/SeedManager"):
		var base_seed = get_node("/root/SeedManager").get_seed()
		var seed_offset = seed_value % 1000
		seed_value = base_seed + seed_offset
		_init_params.seed_value = seed_value
		
		# Regenerate moon texture
		_generate_moon_texture()

# Setup from MoonData method
func setup_from_data(moon_data: MoonData) -> void:
	# Set properties from moon data
	entity_id = moon_data.entity_id
	seed_value = moon_data.seed_value
	moon_name = moon_data.moon_name
	pixel_size = moon_data.pixel_size
	is_gaseous = moon_data.is_gaseous
	moon_type = moon_data.moon_type
	
	# Set orbit parameters
	distance = moon_data.distance
	base_angle = moon_data.base_angle
	orbit_speed = moon_data.orbit_speed
	orbit_deviation = moon_data.orbit_deviation
	phase_offset = moon_data.phase_offset
	orbital_inclination = moon_data.orbital_inclination
	orbit_vertical_offset = moon_data.orbit_vertical_offset
	
	# Set visual properties
	orbit_color = moon_data.orbit_color
	indicator_color = moon_data.indicator_color
	orbit_indicator_size = moon_data.orbit_indicator_size
	
	# Generate texture
	_generate_moon_texture()
	
	# Store parameters for later reference
	_init_params = {
		"entity_id": entity_id,
		"seed_value": seed_value,
		"moon_name": moon_name,
		"pixel_size": pixel_size,
		"is_gaseous": is_gaseous,
		"moon_type": moon_type,
		"distance": distance,
		"base_angle": base_angle,
		"orbit_speed": orbit_speed,
		"orbit_deviation": orbit_deviation,
		"phase_offset": phase_offset,
		"orbital_inclination": orbital_inclination,
		"orbit_vertical_offset": orbit_vertical_offset
	}

# Legacy initialize method for backward compatibility
func initialize(params: Dictionary) -> void:
	# Extract parameters
	seed_value = params.seed_value
	parent_planet = params.parent_planet
	distance = params.distance
	base_angle = params.base_angle
	orbit_speed = params.orbit_speed
	orbit_deviation = params.orbit_deviation
	phase_offset = params.phase_offset
	
	# Optional parameters
	use_texture_cache = params.get("use_texture_cache", true)
	is_gaseous = params.get("is_gaseous", false)
	orbital_inclination = params.get("orbital_inclination", 1.0)
	orbit_vertical_offset = params.get("orbit_vertical_offset", 0.0)
	moon_type = params.get("moon_type", MoonType.ROCKY)
	
	# Moon name
	moon_name = params.get("moon_name", _get_moon_type_prefix() + " Moon-" + str(seed_value % 1000))
	
	# Generate texture
	_generate_moon_texture()
	
	# Set orbit color
	_set_orbit_color()
	
	# Store params for later reference
	_init_params = params.duplicate()

# Generate texture with appropriate type
func _generate_moon_texture() -> void:
	# Calculate cache key based on moon type
	var type_props = TYPE_PROPERTIES.get(moon_type, TYPE_PROPERTIES[MoonType.ROCKY])
	var cache_key = seed_value * 10 + type_props.cache_offset
	
	# Generate or retrieve from cache
	if use_texture_cache and PlanetSpawnerBase.texture_cache != null and PlanetSpawnerBase.texture_cache.moons.has(cache_key):
		# Use cached texture
		moon_texture = PlanetSpawnerBase.texture_cache.moons[cache_key]
		var moon_generator = MoonGenerator.new()
		pixel_size = moon_generator.get_moon_size(seed_value, is_gaseous)
	else:
		# Generate based on type
		var moon_generator = MoonGenerator.new()
		moon_texture = moon_generator.create_moon_texture(seed_value, moon_type, is_gaseous)
		pixel_size = moon_generator.get_moon_size(seed_value, is_gaseous)
		
		# Cache the texture
		if use_texture_cache and PlanetSpawnerBase.texture_cache != null:
			PlanetSpawnerBase.texture_cache.moons[cache_key] = moon_texture

func _set_orbit_color() -> void:
	var type_props = TYPE_PROPERTIES.get(moon_type, TYPE_PROPERTIES[MoonType.ROCKY])
	orbit_color = type_props.orbit_color

func _get_moon_type_prefix() -> String:
	var type_props = TYPE_PROPERTIES.get(moon_type, TYPE_PROPERTIES[MoonType.ROCKY])
	return type_props.prefix
