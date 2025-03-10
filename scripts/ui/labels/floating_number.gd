# scripts/ui/labels/floating_number.gd
# ========================
# Purpose:
#   Animated floating numbers for damage, healing, resource gains, etc.
#   Supports different colors and visual styles based on type

extends BaseLabel
class_name FloatingNumber

# Movement properties
@export var float_speed: float = 60.0
@export var float_distance: float = 80.0
@export var float_direction: Vector2 = Vector2(0, -1)  # Up by default
@export var random_horizontal: float = 30.0  # Random horizontal movement
@export var scale_start: float = 1.2
@export var scale_end: float = 0.8

# Style properties by type
enum NumberType {
	DAMAGE,
	HEALING,
	SCORE,
	RESOURCE,
	CREDITS
}

# Type colors
@export var damage_color: Color = Color(1.0, 0.3, 0.3, 1.0)   # Red
@export var healing_color: Color = Color(0.3, 1.0, 0.3, 1.0)   # Green
@export var score_color: Color = Color(1.0, 0.8, 0.2, 1.0)    # Yellow
@export var resource_color: Color = Color(0.4, 0.7, 1.0, 1.0)  # Blue
@export var credits_color: Color = Color(0.6, 1.0, 0.7, 1.0)   # Money green

# Number formatting
@export var prefix: String = ""
@export var suffix: String = ""
@export var use_plus_minus: bool = true
@export var font_size: int = 20

# Animation tracking
var _start_position: Vector2
var _movement_direction: Vector2
var _value: float = 0.0
var _type_string: String = "default"
var _metadata: Dictionary = {}

# Override setup with value-specific initialization
func setup(param1 = null, param2 = null, param3 = null, param4 = null) -> void:
	# Configure lifetime
	lifetime = 2.0
	fade_in_time = 0.1
	fade_out_time = 0.5
	
	# Extract parameters
	var pos_vector = Vector2.ZERO
	if param1 is Vector2:
		pos_vector = param1
	
	var value = 0.0
	if param2 is float or param2 is int:
		value = float(param2)
	
	var type = "default"
	if param3 is String:
		type = param3
	
	var metadata = null
	if param4 != null:
		metadata = param4
	
	# Store the value and type
	_value = value
	_type_string = type
	
	if metadata != null:
		_metadata = metadata if metadata is Dictionary else {"data": metadata}
	
	# Configure initial scale/opacity
	scale = Vector2.ONE * scale_start
	modulate.a = 0.0  # Start invisible
	
	# Store start position
	_start_position = pos_vector
	
	# Add random horizontal offset
	var h_offset = randf_range(-random_horizontal, random_horizontal)
	_movement_direction = (float_direction + Vector2(h_offset, 0)).normalized()
	
	# Create the visual label if needed
	_create_floating_number()
	
	# Set up text and color
	_configure_appearance()
	
	# Set initial position
	global_position = pos_vector
	
	# Initialize base label
	super.setup(pos_vector, value, type, metadata)

# Create the floating number visual
func _create_floating_number() -> void:
	# Create container if not already created
	if not _container:
		_container = Control.new()
		_container.anchor_left = 0.5
		_container.anchor_top = 0.5
		_container.anchor_right = 0.5
		_container.anchor_bottom = 0.5
		_container.size = Vector2(200, 40)
		_container.position = Vector2(-100, -20)
		add_child(_container)
	
	# Create or update the label
	if not _label:
		_label = Label.new()
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.anchor_right = 1.0
		_label.anchor_bottom = 1.0
		_label.add_theme_font_size_override("font_size", font_size)
		_container.add_child(_label)

# Configure appearance based on type
func _configure_appearance() -> void:
	if not _label:
		return
		
	# Format the value
	var text = _format_value(_value)
	
	# Get color for this type
	var color = _get_type_color()
	
	# Set text and color
	_label.text = text
	_label.add_theme_color_override("font_color", color)
	
	# Apply drop shadow or outline
	if _value >= 100:
		# Make larger values more prominent
		_label.add_theme_font_size_override("font_size", int(font_size * 1.5))
		scale = Vector2.ONE * scale_start * 1.2
	elif _value >= 50:
		_label.add_theme_font_size_override("font_size", int(font_size * 1.2))
		scale = Vector2.ONE * scale_start * 1.1

# Get type color
func _get_type_color() -> Color:
	match _type_string:
		"damage":
			return damage_color
		"healing":
			return healing_color
		"score":
			return score_color
		"resource":
			return resource_color
		"credits":
			return credits_color
		_:
			return Color.WHITE

# Format the value for display
func _format_value(value: float) -> String:
	var formatted = ""
	
	# Add plus sign if needed
	if use_plus_minus and value > 0 and _type_string != "damage":
		formatted += "+"
	
	# Handle special formatting for resources
	if _type_string == "resource" and _metadata.has("resource_name"):
		if abs(value) >= 1000:
			formatted += str(int(value / 100) / 10.0) + "K "
		else:
			formatted += str(int(value)) + " "
		formatted += _metadata.resource_name
		return formatted
	
	# Format based on magnitude
	if abs(value) >= 1000000:
		formatted += str(int(value / 100000) / 10.0) + "M"
	elif abs(value) >= 1000:
		formatted += str(int(value / 100) / 10.0) + "K"
	else:
		# Show decimal point only for specific types
		if _type_string == "healing" and abs(value) < 10 and value != int(value):
			formatted += str(snapped(value, 0.1))
		else:
			formatted += str(int(value))
	
	# Add prefix and suffix
	return prefix + formatted + suffix

# Override process to handle animation
func _process(delta: float) -> void:
	super._process(delta)
	
	if not _initialized or not visible:
		return
	
	# Calculate movement
	var movement = _movement_direction * float_speed * delta
	global_position += movement
	
	# Calculate scale transition
	var scale_factor = 1.0
	if lifetime > 0:
		var progress = _timer / lifetime
		scale_factor = lerp(scale_start, scale_end, progress)
	
	scale = Vector2.ONE * scale_factor
