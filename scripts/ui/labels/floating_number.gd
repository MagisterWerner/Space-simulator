# scripts/ui/labels/floating_number.gd
# ========================
# Purpose:
#   Animated floating numbers for damage, healing, resource gains, etc.
#   Supports different colors and visual styles based on type
#   Uses deterministic randomization to ensure consistent visuals with the same seed

extends BaseLabel
class_name FloatingNumber

# Movement properties
@export var float_speed: float = 60.0       # Speed of upward movement in pixels per second
@export var float_distance: float = 80.0    # Total distance to float before disappearing  
@export var float_direction: Vector2 = Vector2(0, -1)  # Default direction (up)
@export var random_horizontal: float = 30.0 # Maximum random horizontal offset in pixels
@export var scale_start: float = 1.2        # Initial scale (larger for emphasis)
@export var scale_end: float = 0.8          # End scale (smaller as it fades out)

# Style properties by type
enum NumberType {
	DAMAGE,
	HEALING,
	SCORE,
	RESOURCE,
	CREDITS
}

# Type colors - using consistent color scheme across the game
@export var damage_color: Color = Color(1.0, 0.3, 0.3, 1.0)   # Red for damage
@export var healing_color: Color = Color(0.3, 1.0, 0.3, 1.0)   # Green for healing
@export var score_color: Color = Color(1.0, 0.8, 0.2, 1.0)    # Gold/yellow for score
@export var resource_color: Color = Color(0.4, 0.7, 1.0, 1.0)  # Blue for resources
@export var credits_color: Color = Color(0.6, 1.0, 0.7, 1.0)   # Money green for credits

# Number formatting
@export var prefix: String = ""             # Text to display before the number
@export var suffix: String = ""             # Text to display after the number
@export var use_plus_minus: bool = true     # Whether to show +/- signs
@export var font_size: int = 20             # Base font size

# Animation tracking
var _start_position: Vector2                # Starting world position
var _movement_direction: Vector2            # Actual movement direction with randomization
var _value: float = 0.0                     # The numeric value to display
var _type_string: String = "default"        # Type identifier (damage, healing, etc.)
var _metadata: Dictionary = {}              # Additional data for special formatting

# Debug settings
var debug_mode: bool = false

# Override setup with value-specific initialization
func setup(param1 = null, param2 = null, param3 = null, param4 = null) -> void:
	# Configure lifecycle timing
	lifetime = 2.0            # Total time visible (seconds)
	fade_in_time = 0.1        # Time to fade in (seconds)
	fade_out_time = 0.5       # Time to fade out (seconds)
	
	# Check for debug mode from GameSettings
	var main_scene = get_tree().current_scene
	var game_settings = main_scene.get_node_or_null("GameSettings")
	if game_settings:
		debug_mode = game_settings.debug_mode and game_settings.debug_ui
		
		# Connect to debug settings changes
		if not game_settings.is_connected("debug_settings_changed", _on_debug_settings_changed):
			game_settings.connect("debug_settings_changed", _on_debug_settings_changed)
	
	# Extract parameters
	# param1: position vector (Vector2)
	# param2: value (float/int)
	# param3: type string (String)
	# param4: additional metadata (Dictionary or other)
	
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
	
	# Add random horizontal offset using SeedManager when available
	# This makes each number move in a slightly different direction
	# but ensures the same number in the same position always moves the same way
	var h_offset = 0.0
	if Engine.has_singleton("SeedManager"):
		# Generate a deterministic object ID using:
		# 1. The instance ID (unique to this floating number)
		# 2. The number value (ensuring different values behave differently)
		# 3. The position (X/Y coordinates multiplied by different factors)
		var seed_value = get_instance_id() + int(_value * 1000) + int(pos_vector.x * 10) + int(pos_vector.y * 20)
		
		var seed_manager = Engine.get_singleton("SeedManager")
		# Wait for SeedManager to be fully initialized if needed
		if seed_manager.has_method("is_initialized") and not seed_manager.is_initialized and seed_manager.has_signal("seed_initialized"):
			await seed_manager.seed_initialized
			
		# Get a consistent random horizontal offset
		h_offset = seed_manager.get_random_value(seed_value, -random_horizontal, random_horizontal)
	else:
		# Fallback to regular random if SeedManager is not available
		h_offset = randf_range(-random_horizontal, random_horizontal)
	
	# Calculate final movement direction by adding horizontal offset to base direction
	# Normalize to ensure consistent speed regardless of direction
	_movement_direction = (float_direction + Vector2(h_offset, 0)).normalized()
	
	# Create the visual label if needed
	create_floating_number()
	
	# Set up text and color
	configure_appearance()
	
	# Set initial position
	global_position = pos_vector
	
	# Initialize base label
	super.setup(pos_vector, value, type, metadata)
	
	if debug_mode:
		debug_print("Created number " + str(_value) + " of type " + _type_string + " at " + str(pos_vector))

# Handle debug setting changes
func _on_debug_settings_changed(debug_settings: Dictionary) -> void:
	debug_mode = debug_settings.get("master", false) and debug_settings.get("ui", false)

# Debug print function
func debug_print(message: String) -> void:
	if debug_mode:
		if Engine.has_singleton("DebugLogger"):
			DebugLogger.debug("FloatingNumber", message)
		else:
			print("FloatingNumber: " + message)

# Create the floating number visual
func create_floating_number() -> void:
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
func configure_appearance() -> void:
	if not _label:
		return
		
	# Format the value based on type and magnitude
	var text = _format_value(_value)
	
	# Get appropriate color for this number type
	var color = _get_type_color()
	
	# Set text and color
	_label.text = text
	_label.add_theme_color_override("font_color", color)
	
	# Apply scaling based on value magnitude
	# This makes large values more visually prominent
	if _value >= 100:
		# Make larger values more prominent
		_label.add_theme_font_size_override("font_size", int(font_size * 1.5))
		scale = Vector2.ONE * scale_start * 1.2
	elif _value >= 50:
		_label.add_theme_font_size_override("font_size", int(font_size * 1.2))
		scale = Vector2.ONE * scale_start * 1.1

# Get type color
func _get_type_color() -> Color:
	# Return the appropriate color based on the number type
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
# This handles formatting rules for different types of numbers
func _format_value(value: float) -> String:
	var formatted = ""
	
	# Add plus sign for positive values (except damage)
	if use_plus_minus and value > 0 and _type_string != "damage":
		formatted += "+"
	
	# Handle special formatting for resources with names
	if _type_string == "resource" and _metadata.has("resource_name"):
		# Add K suffix for thousands
		if abs(value) >= 1000:
			formatted += str(int(value / 100) / 10.0) + "K "
		else:
			formatted += str(int(value)) + " "
		# Add resource name (e.g. "50 Metal", "1.2K Crystals")
		formatted += _metadata.resource_name
		return formatted
	
	# Format based on magnitude
	# Using K for thousands and M for millions
	if abs(value) >= 1000000:
		formatted += str(int(value / 100000) / 10.0) + "M"
	elif abs(value) >= 1000:
		formatted += str(int(value / 100) / 10.0) + "K"
	else:
		# Show decimal point only for specific types and small values
		# This ensures healing like "2.5" isn't rounded to "3"
		if _type_string == "healing" and abs(value) < 10 and value != int(value):
			formatted += str(snapped(value, 0.1))
		else:
			formatted += str(int(value))
	
	# Add prefix and suffix
	return prefix + formatted + suffix

# Override process to handle animation
func _process(delta: float) -> void:
	# Call base class process (handles fade in/out)
	super._process(delta)
	
	if not _initialized or not visible:
		return
	
	# Move in the calculated direction
	var movement = _movement_direction * float_speed * delta
	global_position += movement
	
	# Calculate scale transition from start to end scale
	# This creates a smooth shrinking effect as the number fades
	var scale_factor = 1.0
	if lifetime > 0:
		var progress = _timer / lifetime
		scale_factor = lerp(scale_start, scale_end, progress)
	
	scale = Vector2.ONE * scale_factor
	
	# Debug logging for disappearing numbers
	if debug_mode and _fading_out and _timer >= lifetime - fade_out_time + fade_out_time * 0.8:
		debug_print("Number " + str(_value) + " fading out, almost gone")
