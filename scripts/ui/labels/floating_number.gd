extends BaseLabel
class_name FloatingNumber

# Movement properties
@export var float_speed := 60.0
@export var float_distance := 80.0
@export var float_direction := Vector2(0, -1)
@export var random_horizontal := 30.0
@export var scale_start := 1.2
@export var scale_end := 0.8

# Number type enum
enum NumberType { DAMAGE, HEALING, SCORE, RESOURCE, CREDITS }

# Type colors
@export var damage_color := Color(1.0, 0.3, 0.3, 1.0)
@export var healing_color := Color(0.3, 1.0, 0.3, 1.0)
@export var score_color := Color(1.0, 0.8, 0.2, 1.0)
@export var resource_color := Color(0.4, 0.7, 1.0, 1.0)
@export var credits_color := Color(0.6, 1.0, 0.7, 1.0)

# Number formatting
@export var prefix := ""
@export var suffix := ""
@export var use_plus_minus := true
@export var font_size := 20

# Animation tracking
var _start_position := Vector2.ZERO
var _movement_direction := Vector2.ZERO
var _value := 0.0
var _type_string := "default"
var _metadata := {}
var debug_mode := false

func setup(position: Vector2, value: float, type: String = "default", metadata = null) -> void:
	lifetime = 2.0
	fade_in_time = 0.1
	fade_out_time = 0.5
	
	_update_debug_mode()
	
	_value = value
	_type_string = type
	
	if metadata != null:
		_metadata = metadata if metadata is Dictionary else {"data": metadata}
	
	scale = Vector2.ONE * scale_start
	modulate.a = 0.0
	
	_start_position = position
	
	# Get deterministic horizontal offset
	var h_offset := _get_horizontal_offset(position)
	
	# Calculate movement direction
	_movement_direction = (float_direction + Vector2(h_offset, 0)).normalized()
	
	_create_visual()
	_configure_appearance()
	
	global_position = position
	
	super.setup(position, value, type, metadata)
	
	if debug_mode:
		_debug_print("Created number " + str(_value) + " of type " + _type_string + " at " + str(position))

func _update_debug_mode() -> void:
	var main_scene = get_tree().current_scene
	var game_settings = main_scene.get_node_or_null("GameSettings")
	if game_settings:
		debug_mode = game_settings.debug_mode and game_settings.debug_ui
		if not game_settings.is_connected("debug_settings_changed", _on_debug_settings_changed):
			game_settings.connect("debug_settings_changed", _on_debug_settings_changed)

func _on_debug_settings_changed(debug_settings: Dictionary) -> void:
	debug_mode = debug_settings.get("master", false) and debug_settings.get("ui", false)

func _debug_print(message: String) -> void:
	if debug_mode:
		if Engine.has_singleton("DebugLogger"):
			DebugLogger.debug("FloatingNumber", message)
		else:
			print("FloatingNumber: " + message)

func _get_horizontal_offset(position: Vector2) -> float:
	var h_offset := 0.0
	
	if Engine.has_singleton("SeedManager"):
		var seed_value = get_instance_id() + int(_value * 1000) + int(position.x * 10) + int(position.y * 20)
		
		var seed_manager = Engine.get_singleton("SeedManager")
		if seed_manager.has_method("is_initialized") and not seed_manager.is_initialized and seed_manager.has_signal("seed_initialized"):
			seed_manager.seed_initialized.connect(func(): pass) # Dummy connection to avoid warning
			return 0.0
			
		h_offset = seed_manager.get_random_value(seed_value, -random_horizontal, random_horizontal)
	else:
		# Fallback to regular random if SeedManager is not available
		h_offset = randf_range(-random_horizontal, random_horizontal)
		
	return h_offset

func _create_visual() -> void:
	if not _container:
		_container = Control.new()
		_container.size = Vector2(200, 40)
		_container.position = Vector2(-100, -20)
		add_child(_container)
		
		_container.anchor_left = 0.5
		_container.anchor_top = 0.5
		_container.anchor_right = 0.5
		_container.anchor_bottom = 0.5
	
	if not _label:
		_label = Label.new()
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.anchor_right = 1.0
		_label.anchor_bottom = 1.0
		_label.add_theme_font_size_override("font_size", font_size)
		_container.add_child(_label)

func _configure_appearance() -> void:
	if not _label:
		return
		
	_label.text = _format_value(_value)
	_label.add_theme_color_override("font_color", _get_type_color())
	
	# Scale based on value magnitude
	if _value >= 100:
		_label.add_theme_font_size_override("font_size", int(font_size * 1.5))
		scale = Vector2.ONE * scale_start * 1.2
	elif _value >= 50:
		_label.add_theme_font_size_override("font_size", int(font_size * 1.2))
		scale = Vector2.ONE * scale_start * 1.1

func _get_type_color() -> Color:
	match _type_string:
		"damage": return damage_color
		"healing": return healing_color
		"score": return score_color
		"resource": return resource_color
		"credits": return credits_color
		_: return Color.WHITE

func _format_value(value: float) -> String:
	var formatted := ""
	
	# Add plus sign for positive values (except damage)
	if use_plus_minus and value > 0 and _type_string != "damage":
		formatted += "+"
	
	# Handle special formatting for resources with names
	if _type_string == "resource" and _metadata.has("resource_name"):
		if abs(value) >= 1000:
			formatted += str(int(value / 100) / 10.0) + "K "
		else:
			formatted += str(int(value)) + " "
		# Add resource name
		formatted += _metadata.resource_name
		return formatted
	
	# Format based on magnitude
	if abs(value) >= 1000000:
		formatted += str(int(value / 100000) / 10.0) + "M"
	elif abs(value) >= 1000:
		formatted += str(int(value / 100) / 10.0) + "K"
	else:
		# Show decimal point only for specific types and small values
		if _type_string == "healing" and abs(value) < 10 and value != int(value):
			formatted += str(snapped(value, 0.1))
		else:
			formatted += str(int(value))
	
	return prefix + formatted + suffix

func _process(delta: float) -> void:
	super._process(delta)
	
	if not _initialized or not visible:
		return
	
	# Move in the calculated direction
	global_position += _movement_direction * float_speed * delta
	
	# Calculate scale transition from start to end
	var scale_factor := scale_start
	if lifetime > 0:
		var progress = _timer / lifetime
		scale_factor = lerp(scale_start, scale_end, progress)
	
	scale = Vector2.ONE * scale_factor
