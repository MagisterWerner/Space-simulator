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

func _ready():
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
	
	# Store if this moon belongs to a gaseous planet
	if "is_gaseous" in params:
		is_gaseous = params.is_gaseous
		
	# Use moon_name from params if provided
	if "moon_name" in params:
		moon_name = params.moon_name
	else:
		# Generate a simple name based on type and seed
		moon_name = _get_moon_type_prefix() + " Moon-" + str(seed_value % 1000)
	
	# Generate moon texture - will set pixel_size correctly based on is_gaseous
	_generate_moon_texture()

# Virtual method to be implemented by subclasses
func _generate_moon_texture() -> void:
	push_error("MoonBase: _generate_moon_texture is a virtual method that should be overridden")

# Virtual method to get moon type prefix
func _get_moon_type_prefix() -> String:
	return "Moon"
