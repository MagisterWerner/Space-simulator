# scripts/entities/moon.gd
# Enhanced moon script with multiple moon type support
extends Node2D

# Moon types must match planet.gd enum
enum MoonType {
	ROCKY,
	ICE,
	LAVA
}

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
var moon_type: int = MoonType.ROCKY  # Default to rocky moon

var name_component
var use_texture_cache: bool = true

func _ready():
	name_component = get_node_or_null("NameComponent")
	# Set appropriate z-index to be behind player but may be in front or behind planet
	# The actual z-index will be dynamically adjusted by parent planet based on orbit position
	# Default to -9, will be set to -12 when behind planet (and atmosphere)
	z_index = -9

func _process(_delta):
	queue_redraw()

func _draw():
	if moon_texture:
		draw_texture(moon_texture, -Vector2(pixel_size, pixel_size) / 2, Color.WHITE)

func initialize(params: Dictionary):
	seed_value = params.seed_value
	parent_planet = params.parent_planet
	distance = params.distance
	base_angle = params.base_angle
	orbit_speed = params.orbit_speed
	orbit_deviation = params.orbit_deviation
	phase_offset = params.phase_offset
	
	if "use_texture_cache" in params:
		use_texture_cache = params.use_texture_cache
		
	# Set moon type if provided, otherwise default to rocky
	if "moon_type" in params:
		moon_type = params.moon_type
	
	# Create a unique cache key that includes both seed and type
	var cache_key = seed_value * 10 + moon_type
	
	# Get texture - either from cache or generate new
	if use_texture_cache and PlanetSpawnerBase.texture_cache != null:
		if PlanetSpawnerBase.texture_cache.moons.has(cache_key):
			# Use cached texture
			moon_texture = PlanetSpawnerBase.texture_cache.moons[cache_key]
			pixel_size = MoonGenerator.new().get_moon_size(seed_value)
		else:
			# Generate and cache texture
			var moon_generator = MoonGenerator.new()
			moon_texture = moon_generator.create_moon_texture(seed_value, moon_type)
			pixel_size = moon_generator.get_moon_size(seed_value)
			PlanetSpawnerBase.texture_cache.moons[cache_key] = moon_texture
	else:
		# Generate without caching
		var moon_data = _generate_moon_data(seed_value, moon_type)
		moon_texture = moon_data.texture
		pixel_size = moon_data.pixel_size
	
	# Set up name component
	name_component = get_node_or_null("NameComponent")
	if name_component:
		# Add moon type to name through NameComponent
		var type_prefix = _get_moon_type_prefix()
		name_component.initialize(seed_value, 0, 0, params.parent_name, type_prefix)
		moon_name = name_component.get_entity_name()
	else:
		# Create a basic name using the moon type and seed
		moon_name = _get_moon_type_prefix() + " Moon-" + str(seed_value % 1000)

func _generate_moon_data(moon_seed: int, type: int) -> Dictionary:
	var moon_generator = MoonGenerator.new()
	var texture = moon_generator.create_moon_texture(moon_seed, type)
	var size = moon_generator.get_moon_size(moon_seed)
	
	return {
		"texture": texture,
		"pixel_size": size
	}

# Helper function to get moon type name prefix
func _get_moon_type_prefix() -> String:
	match moon_type:
		MoonType.ROCKY: return "Rocky"
		MoonType.ICE: return "Icy"
		MoonType.LAVA: return "Volcanic"
		_: return ""
