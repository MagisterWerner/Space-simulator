# scripts/ui/labels/base_label.gd
# ========================
# Purpose:
#   Base class for all in-game labels
#   Handles common functionality for positioning, animation, and lifecycle

extends Node2D
class_name BaseLabel

# Common properties
@export var lifetime: float = 3.0       # How long the label exists (0 = infinite)
@export var fade_in_time: float = 0.2    # Time to fade in
@export var fade_out_time: float = 0.5   # Time to fade out
@export var follow_target: bool = false  # Whether to follow a target
@export var offset: Vector2 = Vector2.ZERO # Offset from target position

# Reference to the camera for positioning
var _camera: Camera2D = null

# Tracking variables
var _timer: float = 0.0
var _target: Node = null
var _target_offset: Vector2 = Vector2.ZERO
var _initialized: bool = false
var _fading_out: bool = false
var _debug_mode: bool = false

# Label container
var _container: Control = null
var _label: Label = null

func _ready() -> void:
	# Find camera
	_camera = get_viewport().get_camera_2d()
	
	# Check for debug mode from GameSettings
	var main_scene = get_tree().current_scene
	var game_settings = main_scene.get_node_or_null("GameSettings")
	if game_settings:
		_debug_mode = game_settings.debug_mode
	
	# By default, not visible until setup
	visible = false
	
	# Create label container if needed
	if not _container:
		_create_label_container()
	
	# Set z-index to be in front of most game elements
	z_index = 100

# Create the label container
func _create_label_container() -> void:
	_container = Control.new()
	_container.anchor_left = 0.5
	_container.anchor_top = 0.5
	_container.anchor_right = 0.5
	_container.anchor_bottom = 0.5
	_container.size = Vector2(200, 50)
	_container.position = Vector2(-100, -25)
	add_child(_container)
	
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.anchor_right = 1.0
	_label.anchor_bottom = 1.0
	_container.add_child(_label)

# Base setup method - override in subclasses
func setup(param1 = null, param2 = null, param3 = null, param4 = null) -> void:
	_timer = 0.0
	_fading_out = false
	modulate.a = 0.0  # Start invisible and fade in
	_initialized = true
	
	# Reset scale
	scale = Vector2.ONE
	
	# Setup completed - now visible
	visible = true

# Update method called every frame
func _process(delta: float) -> void:
	if not _initialized or not visible:
		return
	
	# Update timer
	_timer += delta
	
	# Handle lifetime
	if lifetime > 0 and _timer >= lifetime and not _fading_out:
		_start_fade_out()
	
	# Handle fade in
	if _timer <= fade_in_time:
		modulate.a = _timer / fade_in_time
	
	# Handle fade out
	if _fading_out:
		var fade_progress = (_timer - (lifetime - fade_out_time)) / fade_out_time
		if fade_progress >= 1.0:
			_cleanup()
		else:
			modulate.a = 1.0 - fade_progress
	
	# Update position if following target
	if follow_target and _target and is_instance_valid(_target):
		update_position(_target.global_position)

# Update the label's position (world to screen conversion)
func update_position(world_position: Vector2) -> void:
	if not _camera or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_2d()
		if not _camera:
			return
	
	# Convert world position to screen position
	var screen_position = world_position
	
	# Apply offset
	screen_position += offset + _target_offset
	
	# Update position
	global_position = screen_position

# Start fading out the label
func _start_fade_out() -> void:
	_fading_out = true

# Clean up the label when done
func _cleanup() -> void:
	visible = false
	_initialized = false
	_target = null
	
	# Reset label properties
	if _label:
		_label.text = ""
	
	# Remove from parent if not managed by LabelManager
	if not get_parent() or not get_parent().get_parent() or not get_parent().get_parent().get_parent() or get_parent().get_parent().get_parent().name != "LabelManager":
		queue_free()

# Clear the label (for reuse from pool)
func clear() -> void:
	visible = false
	_initialized = false
	_target = null
	_timer = 0.0
	_fading_out = false
	
	# Reset label properties
	if _label:
		_label.text = ""

# Set the label text
func set_text(text: String) -> void:
	if _label:
		_label.text = text

# Set the label color
func set_color(color: Color) -> void:
	if _label:
		_label.add_theme_color_override("font_color", color)

# Debug helper
func debug_print(message: String) -> void:
	if _debug_mode:
		print("[Label] " + message)
