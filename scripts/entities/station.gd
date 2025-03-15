# scripts/entities/station.gd
extends Node2D
class_name Station

signal player_entered_range
signal player_exited_range
signal station_selected
signal station_deselected
signal trading_started
signal trading_ended

# Station type enum
enum StationType {
	TRADING,
	RESEARCH,
	MILITARY,
	MINING
}

# Core properties
@export var station_type: int = StationType.TRADING
@export var station_name: String = "Trading Station"
@export var level: int = 1
@export var rotation_speed: float = 0.1
@export var interaction_radius: float = 200.0
@export var size: float = 1.0

# Interaction visual settings
@export var marker_color: Color = Color(0.3, 0.8, 1.0, 0.7)
@export var highlight_color: Color = Color(0.4, 0.9, 1.0, 0.9)
@export var detection_color: Color = Color(0.2, 0.7, 0.9, 0.4)

# Market data
var sells_resources = {}
var buys_resources = {}
var available_upgrades = []

# Internal state
var _player_in_range: bool = false
var _selected: bool = false
var _texture_seed: int = 0
var _sprite: Sprite2D
var _interaction_area: Area2D
var _marker: Node2D
var _entity_id: int = 0

# Find required nodes
func _ready() -> void:
	add_to_group("stations")
	
	# Find required nodes
	_sprite = get_node_or_null("Sprite2D")
	_interaction_area = get_node_or_null("InteractionArea")
	_marker = get_node_or_null("Marker")
	
	# Create nodes if they don't exist
	if not _sprite:
		_create_sprite()
	
	if not _interaction_area:
		_create_interaction_area()
	
	if not _marker:
		_create_marker()
	
	# Connect signals
	_connect_signals()
	
	# Apply initial appearance
	_update_appearance()

func _process(delta: float) -> void:
	# Apply station rotation
	if _sprite:
		_sprite.rotation += rotation_speed * delta
	
	# Update marker orientation if it exists
	if _marker:
		_marker.rotation = -rotation  # Keep marker upright
	
	# Draw debug range if selected
	if _selected or _player_in_range:
		queue_redraw()

# Setup from StationData
func setup_from_data(station_data: StationData) -> void:
	# Set core properties
	_entity_id = station_data.entity_id
	station_type = station_data.station_type
	station_name = station_data.station_name
	level = station_data.level
	_texture_seed = station_data.texture_seed
	rotation_speed = station_data.rotation_speed
	size = station_data.size
	
	# Set market data
	sells_resources = station_data.sells_resources.duplicate()
	buys_resources = station_data.buys_resources.duplicate()
	available_upgrades = station_data.available_upgrades.duplicate()
	
	# Set defense and interaction properties
	interaction_radius = station_data.defense_radius
	
	# Update appearance with new data
	_update_appearance()
	
	# Update interaction area size
	if _interaction_area and _interaction_area.get_node_or_null("CollisionShape2D"):
		var shape = _interaction_area.get_node("CollisionShape2D").shape
		if shape is CircleShape2D:
			shape.radius = interaction_radius

# Legacy initialize method for backward compatibility
func initialize(seed_value: int) -> void:
	_texture_seed = seed_value
	_update_appearance()

# Create and set up sprite
func _create_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite2D"
	add_child(_sprite)
	
	# Apply default texture if none generated
	if not _sprite.texture:
		_generate_station_texture()

# Create interaction area
func _create_interaction_area() -> void:
	_interaction_area = Area2D.new()
	_interaction_area.name = "InteractionArea"
	add_child(_interaction_area)
	
	var collision = CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	
	var circle_shape = CircleShape2D.new()
	circle_shape.radius = interaction_radius
	collision.shape = circle_shape
	
	_interaction_area.add_child(collision)

# Create marker for UI/navigation
func _create_marker() -> void:
	_marker = Node2D.new()
	_marker.name = "Marker"
	add_child(_marker)
	
	# The marker will be drawn in _draw

# Connect to required signals
func _connect_signals() -> void:
	if _interaction_area:
		if not _interaction_area.is_connected("body_entered", _on_interaction_area_body_entered):
			_interaction_area.connect("body_entered", _on_interaction_area_body_entered)
		
		if not _interaction_area.is_connected("body_exited", _on_interaction_area_body_exited):
			_interaction_area.connect("body_exited", _on_interaction_area_body_exited)

# Drawing function for debug visualization
func _draw() -> void:
	if _selected or _player_in_range:
		# Draw interaction radius
		var color = highlight_color if _selected else detection_color
		draw_circle(Vector2.ZERO, interaction_radius, color.darkened(0.7))
		draw_arc(Vector2.ZERO, interaction_radius, 0, TAU, 32, color, 2.0)

# Generate station appearance based on type and seed
func _update_appearance() -> void:
	# Generate texture if needed
	if _sprite and not _sprite.texture:
		_generate_station_texture()
	
	# Set appropriate colors based on station type
	match station_type:
		StationType.TRADING:
			marker_color = Color(0.3, 0.8, 1.0, 0.7)
			highlight_color = Color(0.4, 0.9, 1.0, 0.9)
		StationType.RESEARCH:
			marker_color = Color(0.5, 0.3, 0.9, 0.7)
			highlight_color = Color(0.6, 0.4, 1.0, 0.9)
		StationType.MILITARY:
			marker_color = Color(1.0, 0.3, 0.3, 0.7)
			highlight_color = Color(1.0, 0.4, 0.4, 0.9)
		StationType.MINING:
			marker_color = Color(0.8, 0.6, 0.2, 0.7)
			highlight_color = Color(0.9, 0.7, 0.3, 0.9)
	
	# Update visual scale
	if _sprite:
		_sprite.scale = Vector2(size, size)

# Generate station texture
func _generate_station_texture() -> void:
	if not _sprite:
		return
	
	# Find or create generator
	var generator = _find_or_create_generator()
	if not generator:
		# Create a placeholder texture
		_create_placeholder_texture()
		return
	
	# Apply seed and type to generator
	generator.seed_value = _texture_seed
	generator.station_type = station_type
	
	# Generate texture
	var texture = generator.create_station_texture()
	if texture:
		_sprite.texture = texture
	else:
		_create_placeholder_texture()

# Find or create station texture generator
func _find_or_create_generator() -> Node:
	# Find existing generator
	var generators = get_tree().get_nodes_in_group("station_generators")
	for gen in generators:
		return gen
		
	# Create new generator
	var generator_script = load("res://scripts/generators/station_generator.gd")
	if generator_script:
		var generator = generator_script.new()
		generator.add_to_group("station_generators")
		get_tree().current_scene.add_child(generator)
		return generator
	
	return null

# Create a simple placeholder texture
func _create_placeholder_texture() -> void:
	if not _sprite:
		return
	
	# Create a simple colored placeholder based on station type
	var img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	
	# Fill with color based on station type
	var color: Color
	match station_type:
		StationType.TRADING: color = Color(0.3, 0.8, 1.0)
		StationType.RESEARCH: color = Color(0.5, 0.3, 0.9)
		StationType.MILITARY: color = Color(1.0, 0.3, 0.3)
		StationType.MINING: color = Color(0.8, 0.6, 0.2)
		_: color = Color(0.7, 0.7, 0.7)
	
	img.fill(color)
	
	# Draw a basic station shape
	for x in range(64):
		for y in range(64):
			var distance = Vector2(x - 32, y - 32).length()
			if distance > 30:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	
	# Create texture from image
	var tex = ImageTexture.create_from_image(img)
	_sprite.texture = tex

# Set market data
func set_market_data(sell_resources: Dictionary, buy_resources: Dictionary, upgrades: Array) -> void:
	sells_resources = sell_resources.duplicate()
	buys_resources = buy_resources.duplicate()
	available_upgrades = upgrades.duplicate()

# Signal handlers
func _on_interaction_area_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		player_entered_range.emit()
		queue_redraw()

func _on_interaction_area_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		player_exited_range.emit()
		
		# Deselect if player leaves range
		if _selected:
			deselect()
			
		queue_redraw()

# Selection management
func select() -> void:
	if not _selected:
		_selected = true
		station_selected.emit()
		queue_redraw()

func deselect() -> void:
	if _selected:
		_selected = false
		station_deselected.emit()
		queue_redraw()

# Trading management
func start_trading() -> void:
	if _player_in_range:
		trading_started.emit()

func end_trading() -> void:
	trading_ended.emit()

# Get station type name
func get_type_name() -> String:
	match station_type:
		StationType.TRADING: return "Trading"
		StationType.RESEARCH: return "Research"
		StationType.MILITARY: return "Military"
		StationType.MINING: return "Mining"
		_: return "Unknown"

# Get station data for saving/loading
func get_station_data() -> Dictionary:
	return {
		"entity_id": _entity_id,
		"station_type": station_type,
		"station_name": station_name,
		"level": level,
		"texture_seed": _texture_seed,
		"rotation_speed": rotation_speed,
		"size": size,
		"sells_resources": sells_resources,
		"buys_resources": buys_resources,
		"available_upgrades": available_upgrades,
		"position": global_position
	}
