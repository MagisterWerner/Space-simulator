extends BaseLabel
class_name EntityLabel

# Entity label specific properties
@export var show_distance := true
@export var show_type := true
@export var fade_distance := 3000.0
@export var distance_update_interval := 0.5

# Style properties
@export var name_font_size := 16
@export var info_font_size := 12
@export var background_color := Color(0.1, 0.1, 0.2, 0.7)
@export var planet_color := Color(0.2, 0.7, 1.0)
@export var station_color := Color(1.0, 0.5, 0.2)
@export var ship_color := Color(0.2, 1.0, 0.5)
@export var asteroid_color := Color(0.7, 0.7, 0.7)
@export var default_color := Color(1.0, 1.0, 1.0)

# Visual elements
var _background: ColorRect
var _name_label: Label
var _info_label: Label
var _distance_label: Label

# Entity tracking
var _entity: Node
var _entity_type := "entity"
var _distance_timer := 0.0
var _cached_viewport_size: Vector2
var _cached_player_position: Vector2

func _ready() -> void:
	super._ready()
	_create_label_layout()
	
	lifetime = 0 # Infinite lifetime
	follow_target = true
	
	# Initialize cached viewport size
	_cached_viewport_size = get_viewport_rect().size

func _create_label_layout() -> void:
	# Create container
	if _container:
		_container.queue_free()
	
	_container = Control.new()
	_container.size = Vector2(160, 80)
	_container.position = Vector2(-80, -40)
	add_child(_container)
	
	_container.anchor_left = 0.5
	_container.anchor_top = 0.5
	_container.anchor_right = 0.5
	_container.anchor_bottom = 0.5
	
	# Create background panel
	_background = ColorRect.new()
	_background.anchor_right = 1.0
	_background.anchor_bottom = 1.0
	_background.color = background_color
	_container.add_child(_background)
	
	# Create name label
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.anchor_right = 1.0
	_name_label.position.y = 5
	_name_label.add_theme_font_size_override("font_size", name_font_size)
	_container.add_child(_name_label)
	
	# Create info label
	_info_label = Label.new()
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.anchor_right = 1.0
	_info_label.position.y = 30
	_info_label.add_theme_font_size_override("font_size", info_font_size)
	_container.add_child(_info_label)
	
	# Create distance label
	_distance_label = Label.new()
	_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_distance_label.anchor_right = 1.0
	_distance_label.position.y = 50
	_distance_label.add_theme_font_size_override("font_size", info_font_size)
	_container.add_child(_distance_label)

func setup(param1 = null, param2 = null, param3 = null, param4 = null) -> void:
	super.setup(param1, param2, param3, param4)
	
	# Extract parameters with type safety checks
	var entity = param1 as Node
	var label_text = param2 as String
	var entity_type = "entity"
	if param3 != null and param3 is String:
		entity_type = param3
	
	if not entity or not label_text:
		return
	
	_entity = entity
	_entity_type = entity_type
	
	# Set name
	if _name_label:
		_name_label.text = label_text
	
	# Set type info if available
	if _info_label and show_type:
		# Format entity type for display
		var type_display = _get_entity_type_display(entity, entity_type)
		_info_label.text = type_display
	
	# Set color based on entity type
	var color = _get_color_for_entity_type(entity_type)
	if _name_label:
		_name_label.add_theme_color_override("font_color", color)
	
	# Position offset above entity
	offset = Vector2(0, -80)
	_target_offset = Vector2.ZERO
	
	# Make sure we're visible
	visible = true
	modulate.a = 1.0

func _get_entity_type_display(entity: Node, entity_type: String) -> String:
	var type_display = entity_type.capitalize()
	
	if entity.has_method("get_planet_type"):
		type_display = entity.get_planet_type()
	elif entity.has_method("get_station_type"):
		type_display = entity.get_station_type()
	elif entity.get("planet_type") != null:
		type_display = entity.get("planet_type")
	elif entity.get("station_type") != null:
		type_display = entity.get("station_type")
	
	return type_display

func _get_color_for_entity_type(entity_type: String) -> Color:
	match entity_type:
		"planet": return planet_color
		"station": return station_color
		"ship": return ship_color
		"asteroid": return asteroid_color
		_: return default_color

func _process(delta: float) -> void:
	super._process(delta)
	
	if not _initialized or not visible:
		return
	
	# Check if viewport size changed
	var current_viewport_size = get_viewport_rect().size
	if current_viewport_size != _cached_viewport_size:
		_cached_viewport_size = current_viewport_size
	
	# Update distance at intervals
	_distance_timer += delta
	if _distance_timer >= distance_update_interval:
		_distance_timer = 0
		_update_distance()
		
		# Also update distance-based transparency
		_update_distance_fade()

func _update_distance() -> void:
	if not show_distance or not _distance_label or not _entity or not is_instance_valid(_entity):
		return
	
	var player_pos = _get_player_position()
	if player_pos == Vector2.ZERO:
		return
	
	var distance = _entity.global_position.distance_to(player_pos)
	_distance_label.text = _format_distance(distance)

func _update_distance_fade() -> void:
	if fade_distance <= 0 or not _entity or not is_instance_valid(_entity):
		return
		
	var player_pos = _get_player_position()
	if player_pos != Vector2.ZERO:
		var distance = _entity.global_position.distance_to(player_pos)
		var fade_factor = clamp(1.0 - (distance / fade_distance), 0.3, 1.0)
		modulate.a = fade_factor

func _format_distance(distance: float) -> String:
	if distance < 1000:
		return str(int(distance)) + " m"
	else:
		return str(int(distance / 100) / 10.0) + " km"

func _get_player_position() -> Vector2:
	# Only find player every few updates to improve performance
	if _cached_player_position != Vector2.ZERO and _distance_timer < distance_update_interval * 0.5:
		return _cached_player_position
		
	var player_ships = get_tree().get_nodes_in_group("player")
	if player_ships.is_empty():
		return Vector2.ZERO
		
	var player = player_ships[0]
	if not is_instance_valid(player):
		return Vector2.ZERO
	
	_cached_player_position = player.global_position
	return _cached_player_position

func update_position(world_position: Vector2) -> void:
	super.update_position(world_position)
	_keep_on_screen()

func _keep_on_screen() -> void:
	var viewport_transform = get_viewport_transform()
	var viewport_size = _cached_viewport_size
	var margin = Vector2(20, 20)
	
	# Calculate label boundaries in viewport coordinates
	var label_size = _container.size * scale.x
	var min_pos = margin
	var max_pos = viewport_size - label_size - margin
	
	# Get current position in viewport coordinates
	var viewport_pos = viewport_transform * global_position
	
	# Calculate clamped position
	var need_clamp = false
	var clamped_pos = viewport_pos
	
	if viewport_pos.x < min_pos.x:
		clamped_pos.x = min_pos.x
		need_clamp = true
	elif viewport_pos.x > max_pos.x:
		clamped_pos.x = max_pos.x
		need_clamp = true
	
	if viewport_pos.y < min_pos.y:
		clamped_pos.y = min_pos.y
		need_clamp = true
	elif viewport_pos.y > max_pos.y:
		clamped_pos.y = max_pos.y
		need_clamp = true
	
	# Apply clamped position if needed
	if need_clamp:
		global_position = viewport_transform.affine_inverse() * clamped_pos

func clear() -> void:
	super.clear()
	
	_entity = null
	_entity_type = "entity"
	_distance_timer = 0.0
	_cached_player_position = Vector2.ZERO
	
	if _name_label:
		_name_label.text = ""
	
	if _info_label:
		_info_label.text = ""
	
	if _distance_label:
		_distance_label.text = ""
