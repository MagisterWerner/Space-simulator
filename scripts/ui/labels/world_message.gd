# scripts/ui/labels/world_message.gd
# ========================
# Purpose:
#   Large, centered text notifications for game events
#   Handles alert messages, tutorials, game events, etc.

extends BaseLabel
class_name WorldMessage

# Message styles
enum MessageType {
	DEFAULT,
	WARNING,
	SUCCESS,
	INFO,
	TUTORIAL,
	ACHIEVEMENT,
	RESOURCE
}

# Message positions
enum ScreenPosition {
	CENTER,
	TOP,
	BOTTOM,
	TOP_LEFT,
	TOP_RIGHT,
	BOTTOM_LEFT,
	BOTTOM_RIGHT
}

# Style properties
@export var font_size: int = 24
@export var padding: float = 20.0
@export var background_color: Color = Color(0.1, 0.1, 0.2, 0.7)
@export var border_color: Color = Color(0.5, 0.5, 0.8, 0.8)
@export var border_width: float = 2.0
@export var screen_position: String = "center"

# Type-specific colors
@export var default_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var warning_color: Color = Color(1.0, 0.7, 0.2, 1.0)
@export var success_color: Color = Color(0.2, 1.0, 0.4, 1.0)
@export var info_color: Color = Color(0.4, 0.8, 1.0, 1.0)
@export var tutorial_color: Color = Color(0.8, 0.8, 1.0, 1.0)
@export var achievement_color: Color = Color(1.0, 0.9, 0.3, 1.0)
@export var resource_color: Color = Color(0.5, 0.9, 0.7, 1.0)

# Animation properties
@export var use_slide_animation: bool = true
@export var slide_distance: float = 100.0
@export var slide_duration: float = 0.5
@export var pulse_effect: bool = false
@export var pulse_scale: float = 1.1
@export var pulse_speed: float = 2.0

# Visual elements
var _background: ColorRect
var _border: Control
var _icon: TextureRect = null
var _message_text: String = ""
var _message_type: String = "default"
var _viewport_size: Vector2 = Vector2.ZERO
var _target_position: Vector2 = Vector2.ZERO
var _start_slide_position: Vector2 = Vector2.ZERO

# Override setup with message-specific initialization
func setup(param1 = null, param2 = null, param3 = null, param4 = null) -> void:
	# Configure lifetime
	lifetime = 3.0
	fade_in_time = 0.3
	fade_out_time = 0.5
	
	# Extract parameters
	var message = ""
	if param1 is String:
		message = param1
	
	var duration = 3.0
	if param2 is float or param2 is int:
		duration = float(param2)
		lifetime = duration
	
	var type = "default"
	if param3 is String:
		type = param3
	
	var position = "center"
	if param4 is String:
		position = param4
	elif param4 is Vector2:
		_viewport_size = param4
	
	# Store the message and type
	_message_text = message
	_message_type = type
	screen_position = position
	
	# Get viewport size if not provided
	if _viewport_size == Vector2.ZERO:
		_viewport_size = get_viewport_rect().size
	
	# Create or update the visual elements
	_create_message_visuals()
	
	# Set text and color based on type
	_configure_appearance()
	
	# Set initial position
	_calculate_position()
	
	# Initialize animation
	if use_slide_animation:
		_start_slide_position = global_position
		match screen_position:
			"top", "top_left", "top_right":
				global_position.y -= slide_distance
			"bottom", "bottom_left", "bottom_right":
				global_position.y += slide_distance
			_:  # Center and other positions
				global_position.y += slide_distance
	
	# Initialize base label
	super.setup(message, duration, type, position)

# Create the message visuals
func _create_message_visuals() -> void:
	# Create container if not already created
	if not _container:
		_container = Control.new()
		add_child(_container)
	
	# Create background panel
	if not _background:
		_background = ColorRect.new()
		_background.color = background_color
		_container.add_child(_background)
	
	# Create border
	if not _border:
		_border = Control.new()
		_container.add_child(_border)
	
	# Create or update the label
	if not _label:
		_label = Label.new()
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.add_theme_font_size_override("font_size", font_size)
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_container.add_child(_label)
	
	# Create icon if needed (placeholders for now)
	if _message_type in ["warning", "success", "info", "tutorial", "achievement"] and not _icon:
		_icon = TextureRect.new()
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.custom_minimum_size = Vector2(32, 32)
		_container.add_child(_icon)

# Configure appearance based on type
func _configure_appearance() -> void:
	if not _label:
		return
	
	# Set the message text
	_label.text = _message_text
	
	# Calculate size based on text
	var min_width = 300
	var max_width = _viewport_size.x * 0.7
	var text_size = _label.get_theme_font("font").get_string_size(_message_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _label.get_theme_font_size("font_size"))
	
	var width = clamp(text_size.x + padding * 2, min_width, max_width)
	var height = 70  # Minimum height
	
	if text_size.x > max_width - padding * 2:
		# Text will wrap, so we need more height
		_label.custom_minimum_size.x = max_width - padding * 2
		# Wait a frame so the label can calculate its wrapped height
		await get_tree().process_frame
		height = _label.get_minimum_size().y + padding * 2
	
	# Set container size
	_container.custom_minimum_size = Vector2(width, height)
	_container.size = Vector2(width, height)
	_container.position = Vector2(-width/2, -height/2)
	
	# Update background and border
	_background.size = _container.size
	
	# Get color for this type
	var color = _get_type_color()
	
	# Apply color
	_label.add_theme_color_override("font_color", color)
	_border.modulate = color
	
	# Load icon if appropriate
	if _icon:
		# In a real implementation, we would load actual textures here
		_icon.visible = _message_type in ["warning", "success", "info", "tutorial", "achievement"]
		if _icon.visible:
			_icon.position = Vector2(padding, (_container.size.y - _icon.custom_minimum_size.y) / 2)
			_label.position.x = _icon.position.x + _icon.custom_minimum_size.x + padding / 2

# Calculate position based on screen position setting
func _calculate_position() -> void:
	var margin = 50  # Distance from screen edges
	
	match screen_position:
		"top":
			_target_position = Vector2(_viewport_size.x / 2, margin + _container.size.y / 2)
		"bottom":
			_target_position = Vector2(_viewport_size.x / 2, _viewport_size.y - margin - _container.size.y / 2)
		"top_left":
			_target_position = Vector2(margin + _container.size.x / 2, margin + _container.size.y / 2)
		"top_right":
			_target_position = Vector2(_viewport_size.x - margin - _container.size.x / 2, margin + _container.size.y / 2)
		"bottom_left":
			_target_position = Vector2(margin + _container.size.x / 2, _viewport_size.y - margin - _container.size.y / 2)
		"bottom_right":
			_target_position = Vector2(_viewport_size.x - margin - _container.size.x / 2, _viewport_size.y - margin - _container.size.y / 2)
		_:  # Default to center
			_target_position = Vector2(_viewport_size.x / 2, _viewport_size.y / 2)
	
	# Set actual position
	global_position = _target_position

# Get type color
func _get_type_color() -> Color:
	match _message_type:
		"warning":
			return warning_color
		"success":
			return success_color
		"info":
			return info_color
		"tutorial":
			return tutorial_color
		"achievement":
			return achievement_color
		"resource":
			return resource_color
		_:
			return default_color

# Override process to handle animation
func _process(delta: float) -> void:
	super._process(delta)
	
	if not _initialized or not visible:
		return
	
	# Handle slide-in animation
	if use_slide_animation and _timer < slide_duration:
		var progress = _timer / slide_duration
		var ease_progress = ease(progress, 0.5)  # Ease out
		global_position = lerp(_start_slide_position, _target_position, ease_progress)
	
	# Handle pulse effect
	if pulse_effect and not _fading_out:
		var pulse = sin(_timer * pulse_speed) * 0.5 + 0.5
		var pulse_amount = 1.0 + (pulse_scale - 1.0) * pulse
		scale = Vector2.ONE * pulse_amount

# Handle viewport resize
func on_viewport_resize(new_size: Vector2) -> void:
	_viewport_size = new_size
	
	if _initialized and visible:
		# Recalculate position for the new viewport size
		_calculate_position()
		
		# Update target position for any in-progress animations
		_target_position = global_position
