# scripts/entities/moon.gd
# Enhanced moon script with support for multiple moon types and procedural generation
extends Node2D
class_name Moon

# Moon types must match planet.gd enum
enum MoonType {
	ROCKY,
	ICE,
	LAVA
}

signal property_changed(property_name, old_value, new_value)

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
var _debug_mode: bool = false

func _ready() -> void:
	name_component = get_node_or_null("NameComponent")
	# Set appropriate z-index to be behind player but may be in front or behind planet
	# The actual z-index will be dynamically adjusted by parent planet based on orbit position
	# Default to -9, will be set to -12 when behind planet (and atmosphere)
	z_index = -9

func _process(_delta) -> void:
	queue_redraw()

func _draw() -> void:
	if moon_texture:
		draw_texture(moon_texture, -Vector2(pixel_size, pixel_size) / 2, Color.WHITE)

# PUBLIC API

## Initialize the moon with parameters
func initialize(params: Dictionary) -> void:
	seed_value = params.seed_value
	parent_planet = params.parent_planet
	distance = params.distance
	base_angle = params.base_angle
	orbit_speed = params.orbit_speed
	orbit_deviation = params.orbit_deviation
	phase_offset = params.phase_offset
	
	if params.has("use_texture_cache"):
		use_texture_cache = params.use_texture_cache
	
	if params.has("debug_mode"):
		_debug_mode = params.debug_mode
		
	# Set moon type if provided, otherwise default to rocky
	if params.has("moon_type"):
		moon_type = params.moon_type
	
	# Create a unique cache key that includes both seed and type
	var cache_key = seed_value * 10 + moon_type
	
	# Get texture - either from cache or generate new
	if use_texture_cache and PlanetSpawner.texture_cache != null:
		if PlanetSpawner.texture_cache.moons.has(cache_key):
			# Use cached texture
			moon_texture = PlanetSpawner.texture_cache.moons[cache_key]
			pixel_size = MoonGenerator.new().get_moon_size(seed_value)
		else:
			# Generate and cache texture
			var moon_generator = MoonGenerator.new()
			moon_texture = moon_generator.create_moon_texture(seed_value, moon_type)
			pixel_size = moon_generator.get_moon_size(seed_value)
			PlanetSpawner.texture_cache.moons[cache_key] = moon_texture
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

## Set a moon property and emit the property_changed signal
func set_property(property_name: String, value) -> void:
	if has_property(self, property_name):
		var old_value = get(property_name)
		set(property_name, value)
		property_changed.emit(property_name, old_value, value)

## Check if a property exists
static func has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if property.name == property_name:
			return true
	return false

## Get the moon type as a string
func get_moon_type_name() -> String:
	match moon_type:
		MoonType.ROCKY: return "Rocky"
		MoonType.ICE: return "Icy"
		MoonType.LAVA: return "Volcanic"
		_: return "Unknown"

## Get the parent planet
func get_parent_planet() -> Node:
	return parent_planet

## Set the orbit speed
func set_orbit_speed(new_speed: float) -> void:
	orbit_speed = new_speed

## Set the distance from parent planet
func set_distance(new_distance: float) -> void:
	distance = new_distance

## Set the orbit deviation (ellipse shape)
func set_orbit_deviation(new_deviation: float) -> void:
	orbit_deviation = new_deviation

# PRIVATE METHODS

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
