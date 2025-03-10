# scripts/entities/moons/moon_base.gd
# Base class for all moon types
extends Node2D
class_name MoonBase

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
var is_gaseous: bool = false  # Flag to indicate if moon belongs to a gaseous planet

# Terran planet moon orbit properties
var orbit_is_tilted: bool = false
var tilt_angle: float = 0.0
var tilt_amount: float = 0.0

# Gaseous planet moon properties
var ring_name: String = ""

# Components
var name_component

func _ready():
	name_component = get_node_or_null("NameComponent")
	
	# Set appropriate z-index to be behind player but may be in front or behind planet
	# Z-index will be dynamically adjusted by parent planet based on orbit position
	# Default to -9 (in front of planet), will be set to -12 when behind planet (and atmosphere)
	z_index = -9

func _process(_delta):
	queue_redraw()

func _draw():
	if moon_texture:
		draw_texture(moon_texture, -Vector2(pixel_size, pixel_size) / 2, Color.WHITE)

func initialize(params: Dictionary) -> void:
	seed_value = params.seed_value
	parent_planet = params.parent_planet
	distance = params.distance
	base_angle = params.base_angle
	orbit_speed = params.orbit_speed
	orbit_deviation = params.orbit_deviation
	phase_offset = params.phase_offset
	
	# Optional parameters
	if "use_texture_cache" in params:
		use_texture_cache = params.use_texture_cache
	
	# Store if this moon belongs to a gaseous planet
	if "is_gaseous" in params:
		is_gaseous = params.is_gaseous
	
	# Store ring name if provided (for gaseous planet moons)
	if "ring_name" in params:
		ring_name = params.ring_name
	
	# Store orbit tilt properties if provided (for terran planet moons)
	if "orbit_is_tilted" in params:
		orbit_is_tilted = params.orbit_is_tilted
		
		if "tilt_angle" in params:
			tilt_angle = params.tilt_angle
		
		if "tilt_amount" in params:
			tilt_amount = params.tilt_amount
	
	# Generate moon texture - will set pixel_size correctly based on is_gaseous
	_generate_moon_texture(params)
	
	# Set up name component
	_setup_name_component(params)

# Generate moon texture
func _generate_moon_texture(params: Dictionary) -> void:
	# Get moon type from params
	var moon_type = params.get("moon_type", 0)  # Default to ROCKY
	
	# Create a unique cache key that includes both seed and type
	var cache_key = seed_value * 100 + moon_type * 10 + (1 if is_gaseous else 0)
	
	# Get texture - either from cache or generate new
	if use_texture_cache and PlanetSpawnerBase.texture_cache != null:
		if PlanetSpawnerBase.texture_cache.moons.has(cache_key):
			# Use cached texture
			moon_texture = PlanetSpawnerBase.texture_cache.moons[cache_key]
			var moon_generator = MoonGenerator.new()
			pixel_size = moon_generator.get_moon_size(seed_value, is_gaseous)
		else:
			# Generate and cache texture
			var moon_generator = MoonGenerator.new()
			moon_texture = moon_generator.create_moon_texture(seed_value, moon_type, is_gaseous)
			pixel_size = moon_generator.get_moon_size(seed_value, is_gaseous)
			PlanetSpawnerBase.texture_cache.moons[cache_key] = moon_texture
	else:
		# Generate without caching
		var moon_generator = MoonGenerator.new()
		moon_texture = moon_generator.create_moon_texture(seed_value, moon_type, is_gaseous)
		pixel_size = moon_generator.get_moon_size(seed_value, is_gaseous)

# Setup name component
func _setup_name_component(params: Dictionary) -> void:
	name_component = get_node_or_null("NameComponent")
	if name_component:
		# Add moon type to name through NameComponent
		var type_prefix = _get_moon_type_prefix()
		var parent_name = params.get("parent_name", "")
		
		# Add ring designation if this is a gaseous planet moon
		if is_gaseous and ring_name != "":
			type_prefix = ring_name + " " + type_prefix
		
		# Call initialize on the name component
		if name_component.has_method("initialize"):
			name_component.initialize(seed_value, 0, 0, parent_name, type_prefix)
			moon_name = name_component.get_entity_name()
		else:
			# Fallback if no initialize method
			moon_name = type_prefix + " Moon-" + str(seed_value % 1000)
	else:
		# Create a basic name using the moon type and seed
		var type_prefix = _get_moon_type_prefix()
		if is_gaseous and ring_name != "":
			type_prefix = ring_name + " " + type_prefix
		
		moon_name = type_prefix + " Moon-" + str(seed_value % 1000)

# Virtual method to get moon type prefix
func _get_moon_type_prefix() -> String:
	return "Moon"
