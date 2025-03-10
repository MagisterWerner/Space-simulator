# scripts/entities/moons/moon_base.gd
# Base class for all moon types with improved visual indicators
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

# Visual indicator properties
var orbit_color: Color = Color(1, 1, 1, 0.5)  # Default orbit color
var orbit_indicator_size: float = 4.0         # Size of the orbit indicator in debug mode

# New orbital parameters for different planet types
var orbital_inclination: float = 1.0  # For 3D orbit projection (1.0 = circular)
var orbit_vertical_offset: float = 0.0  # Offset from the equatorial plane

func _ready() -> void:
	# Set z-index appropriately - will be adjusted dynamically based on moon type
	# for gaseous planets to ensure consistent visual hierarchy
	z_index = -9
	
	# Set orbit color based on moon type
	_set_orbit_color()

func _process(_delta) -> void:
	queue_redraw()

func _draw() -> void:
	if moon_texture:
		# Draw moon texture centered at the origin (the moon's position)
		draw_texture(moon_texture, -Vector2(pixel_size, pixel_size) / 2, Color.WHITE)
		
		# Optional: Draw a small indicator showing the moon type
		if parent_planet and parent_planet.debug_draw_orbits:
			var indicator_color = _get_type_color()
			draw_circle(Vector2.ZERO, orbit_indicator_size, indicator_color)

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
		
	# Initialize new orbital parameters
	if "orbital_inclination" in params:
		orbital_inclination = params.orbital_inclination
	if "orbit_vertical_offset" in params:
		orbit_vertical_offset = params.orbit_vertical_offset
		
	# Use moon_name from params if provided
	if "moon_name" in params:
		moon_name = params.moon_name
	else:
		# Generate a simple name based on type and seed
		moon_name = _get_moon_type_prefix() + " Moon-" + str(seed_value % 1000)
	
	# Generate moon texture - will set pixel_size correctly based on is_gaseous
	_generate_moon_texture()
	
	# Set orbit color based on moon type
	_set_orbit_color()
	
	# NOTE: The position is now set by the parent planet after initialization
	# This ensures the moon starts at the correct position on its orbit

# Set the orbit color based on moon type for visual identification
func _set_orbit_color() -> void:
	match _get_moon_type_prefix():
		"Volcanic":
			orbit_color = Color(1.0, 0.3, 0.0, 0.5)  # Orange-red for volcanic (closest)
		"Rocky":
			orbit_color = Color(0.7, 0.7, 0.7, 0.5)  # Gray for rocky (middle)
		"Icy":
			orbit_color = Color(0.5, 0.8, 1.0, 0.5)  # Light blue for icy (furthest)
		_:
			orbit_color = Color(1.0, 1.0, 1.0, 0.5)  # White default

# Get color for type indicator
func _get_type_color() -> Color:
	match _get_moon_type_prefix():
		"Volcanic":
			return Color(1.0, 0.3, 0.0, 0.8)  # Bright orange-red
		"Rocky":
			return Color(0.8, 0.8, 0.8, 0.8)  # Bright gray
		"Icy":
			return Color(0.6, 0.9, 1.0, 0.8)  # Bright blue
		_:
			return Color(1.0, 1.0, 1.0, 0.8)  # White default

# Virtual method to be implemented by subclasses
func _generate_moon_texture() -> void:
	push_error("MoonBase: _generate_moon_texture is a virtual method that should be overridden")

# Virtual method to get moon type prefix
func _get_moon_type_prefix() -> String:
	return "Moon"
