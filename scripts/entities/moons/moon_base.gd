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
var size_scale: float = 1.0  # Added for moon size scaling
var is_gaseous: bool = false  # Flag to indicate if moon belongs to a gaseous planet

# Components
var name_component

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

func initialize(params: Dictionary) -> void:
	seed_value = params.seed_value
	parent_planet = params.parent_planet
	distance = params.distance
	base_angle = params.base_angle
	orbit_speed = params.orbit_speed
	orbit_deviation = params.orbit_deviation
	phase_offset = params.phase_offset
	
	if "use_texture_cache" in params:
		use_texture_cache = params.use_texture_cache
	
	# Apply size scale if provided
	if "size_scale" in params:
		size_scale = params.size_scale
	
	# Store if this moon belongs to a gaseous planet
	if "is_gaseous" in params:
		is_gaseous = params.is_gaseous
	
	# Generate moon texture
	_generate_moon_texture()
	
	# Apply size scaling after generating texture
	pixel_size = int(pixel_size * size_scale)
	
	# Set up name component
	_setup_name_component(params)

# Virtual method to be implemented by subclasses
func _generate_moon_texture() -> void:
	push_error("MoonBase: _generate_moon_texture is a virtual method that should be overridden")

# Setup name component
func _setup_name_component(params: Dictionary) -> void:
	name_component = get_node_or_null("NameComponent")
	if name_component:
		# Add moon type to name through NameComponent
		var type_prefix = _get_moon_type_prefix()
		var parent_name = params.get("parent_name", "")
		
		# Call initialize on the name component
		if name_component.has_method("initialize"):
			name_component.initialize(seed_value, 0, 0, parent_name, type_prefix)
			moon_name = name_component.get_entity_name()
		else:
			# Fallback if no initialize method
			moon_name = type_prefix + " Moon-" + str(seed_value % 1000)
	else:
		# Create a basic name using the moon type and seed
		moon_name = _get_moon_type_prefix() + " Moon-" + str(seed_value % 1000)

# Virtual method to get moon type prefix
func _get_moon_type_prefix() -> String:
	return "Moon"
