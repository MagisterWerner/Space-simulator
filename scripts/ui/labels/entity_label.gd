# scripts/ui/labels/entity_label.gd
# ========================
# Purpose:
#   Labels for in-game entities like planets, stations, ships
#   Displays name, distance, and other relevant information

extends BaseLabel
class_name EntityLabel

# Entity label specific properties
@export var show_distance: bool = true
@export var show_type: bool = true
@export var fade_distance: float = 3000.0
@export var distance_update_interval: float = 0.5

# Style properties
@export var name_font_size: int = 16
@export var info_font_size: int = 12
@export var background_color: Color = Color(0.1, 0.1, 0.2, 0.7)
@export var planet_color: Color = Color(0.2, 0.7, 1.0)
@export var station_color: Color = Color(1.0, 0.5, 0.2)
@export var ship_color: Color = Color(0.2, 1.0, 0.5)
@export var asteroid_color: Color = Color(0.7, 0.7, 0.7)
@export var default_color: Color = Color(1.0, 1.0, 1.0)

# Visual elements
var _background: ColorRect
var _name_label: Label
var _info_label: Label
var _distance_label: Label
var _icon: TextureRect

# Entity tracking
var _entity: Node
var _entity_type: String = "entity"
var _distance_timer: float = 0.0

# Override base _ready to create our specific layout
func _ready() -> void:
	# Call parent ready
	super._ready()
	
	# Create label structure
	_create_entity_label_layout()
	
	# Set infinite lifetime for entity labels
	lifetime = 0
	
	# Always follow target
	follow_target = true

# Create the entity label layout
func _create_entity_label_layout() -> void:
	# Create container
	if _container:
		_container.queue_free()
	
	_container = Control.new()
	_container.anchor_left = 0.5
	_container.anchor_top = 0.5
	_container.anchor_right = 0.5
	_container.anchor_bottom = 0.5
	_container.size = Vector2(160, 80)
	_container.position = Vector2(-80, -40)
	add_child(_container)
	
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

# Setup the entity label
func setup(param1 = null, param2 = null, param3 = null, param4 = null) -> void:
	# Call parent setup
	super.setup(param1, param2, param3, param4)
	
	# Extract parameters
	var entity = param1 as Node
	var label_text = param2 as String
	var entity_type = "entity"
	if param3 != null and param3 is String:
		entity_type = param3
	
	# Skip if invalid parameters
	if not entity or not label_text:
		return
	
	# Store entity reference
	_entity = entity
	_entity_type = entity_type
	
	# Set name
	if _name_label:
		_name_label.text = label_text
	
	# Set type info if available
	if _info_label and show_type:
		# Format entity type for display
		var type_display = entity_type.capitalize()
		
		# Try to get more specific type information
		if entity.has_method("get_planet_type"):
			type_display = entity.get_planet_type()
		elif entity.has_method("get_station_type"):
			type_display = entity.get_station_type()
		elif entity.get("planet_type") != null:
			type_display = entity.get("planet_type")
		elif entity.get("station_type") != null:
			type_display = entity.get("station_type")
		
		_info_label.text = type_display
	
	# Set color based on entity type
	var color = default_color
	match entity_type:
		"planet":
			color = planet_color
		"station":
			color = station_color
		"ship":
			color = ship_color
		"asteroid":
			color = asteroid_color
	
	if _name_label:
		_name_label.add_theme_color_override("font_color", color)
	
	# Position offset above entity
	offset = Vector2(0, -80)
	_target_offset = Vector2(0, 0)
	
	# Make sure we're visible
	visible = true
	modulate.a = 1.0

# Override process to update distance
func _process(delta: float) -> void:
	# Call parent process
	super._process(delta)
	
	# Skip if not initialized or not visible
	if not _initialized or not visible:
		return
	
	# Update distance at intervals
	_distance_timer += delta
	if _distance_timer >= distance_update_interval:
		_distance_timer = 0
		_update_distance()
	
	# Apply distance-based scaling and transparency
	if fade_distance > 0 and _entity and is_instance_valid(_entity):
		var player_pos = _get_player_position()
		if player_pos != Vector2.ZERO:
			var distance = _entity.global_position.distance_to(player_pos)
			var fade_factor = clamp(1.0 - (distance / fade_distance), 0.3, 1.0)
			
			# Apply fade factor
			modulate.a = fade_factor

# Update the distance to player
func _update_distance() -> void:
	if not show_distance or not _distance_label or not _entity or not is_instance_valid(_entity):
		return
	
	var player_pos = _get_player_position()
	if player_pos == Vector2.ZERO:
		return
	
	var distance = _entity.global_position.distance_to(player_pos)
	
	# Format distance for display
	var distance_text = _format_distance(distance)
	_distance_label.text = distance_text

# Format distance value
func _format_distance(distance: float) -> String:
	if distance < 1000:
		return str(int(distance)) + " m"
	else:
		return str(int(distance / 100) / 10.0) + " km"

# Get player position
func _get_player_position() -> Vector2:
	var player_ships = get_tree().get_nodes_in_group("player")
	if player_ships.is_empty():
		return Vector2.ZERO
		
	var player = player_ships[0]
	if not is_instance_valid(player):
		return Vector2.ZERO
		
	return player.global_position

# Override update_position to handle screen boundaries
func update_position(world_position: Vector2) -> void:
	# Call parent update
	super.update_position(world_position)
	
	# Make sure label stays on screen
	_keep_on_screen()

# Keep label within screen bounds
func _keep_on_screen() -> void:
	# Get viewport size and add some margin
	var viewport_size = get_viewport_rect().size
	var margin = Vector2(20, 20)
	
	# Calculate label boundaries in viewport coordinates
	var label_size = _container.size * scale.x
	var min_pos = margin
	var max_pos = viewport_size - label_size - margin
	
	# Get current position in viewport coordinates
	var viewport_pos = get_viewport_transform() * global_position
	
	# Clamp to screen bounds
	var clamped_pos = Vector2(
		clamp(viewport_pos.x, min_pos.x, max_pos.x),
		clamp(viewport_pos.y, min_pos.y, max_pos.y)
	)
	
	# Apply clamped position if needed
	if viewport_pos != clamped_pos:
		global_position = get_viewport_transform().affine_inverse() * clamped_pos

# Override clear for reuse from pool
func clear() -> void:
	super.clear()
	
	_entity = null
	_entity_type = "entity"
	_distance_timer = 0.0
	
	if _name_label:
		_name_label.text = ""
	
	if _info_label:
		_info_label.text = ""
	
	if _distance_label:
		_distance_label.text = ""
