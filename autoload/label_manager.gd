# autoload/label_manager.gd
# ========================
# Purpose:
#   Manages in-game labels and text indicators
#   Handles pooling of label objects for performance
#   Provides API for creating various label types
#
# Examples:
#   Create a label for a planet or station
#    LabelManager.create_entity_label(entity, "Planet Name", "planet")
#
#   Show damage or other numeric values
#    LabelManager.create_floating_number(position, 50, "damage")
#
#   Display important messages
#   LabelManager.show_world_message("Mission Complete!", 3.0, "success")
# ========================

extends Node

# Configuration properties
@export_category("Label Settings")
@export var show_damage_numbers: bool = true
@export var show_entity_labels: bool = true
@export var show_world_messages: bool = true
@export var label_scale: float = 1.0
@export var max_visible_distance: float = 5000.0

@export_category("Pool Sizes")
@export var entity_label_pool_size: int = 20
@export var floating_number_pool_size: int = 50
@export var world_message_pool_size: int = 5

@export_category("Debug")
@export var debug_mode: bool = false

# Reference to game settings
var game_settings: GameSettings = null

# Label pools
var _entity_label_pool: Array = []
var _floating_number_pool: Array = []
var _world_message_pool: Array = []

# Entity tracking
var _labeled_entities: Dictionary = {}  # entity_id -> label instance
var _camera: Camera2D = null
var _viewport_size: Vector2 = Vector2.ZERO

# Label scenes
var entity_label_scene: PackedScene
var floating_number_scene: PackedScene
var world_message_scene: PackedScene

# Queue for world messages
var _message_queue: Array = []
var _current_world_message: Node = null

# Entity label timeout (how often to check visibility)
var _entity_label_check_time: float = 0.0
const ENTITY_LABEL_CHECK_INTERVAL: float = 0.5

# Initialization
func _ready() -> void:
	# Configure this node to continue during pause
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Find GameSettings in the main scene
	_find_game_settings()
	
	# Get viewport size
	_viewport_size = get_viewport().get_visible_rect().size
	
	# Initialize label scenes
	_load_label_scenes()
	
	# Create label container if it doesn't exist
	_create_label_container()
	
	# Initialize label pools
	_initialize_label_pools()
	
	# Connect to entity manager signals
	if has_node("/root/EntityManager"):
		EntityManager.entity_spawned.connect(_on_entity_spawned)
		EntityManager.entity_despawned.connect(_on_entity_despawned)
	
	# Connect to event manager signals
	if has_node("/root/EventManager"):
		# Connect to relevant events
		EventManager.safe_connect("player_damaged", _on_player_damaged)
		EventManager.safe_connect("enemy_destroyed", _on_enemy_destroyed)
		EventManager.safe_connect("resource_collected", _on_resource_collected)
	
	debug_print("Label Manager initialized")

func _find_game_settings() -> void:
	# Try to find GameSettings in the main scene
	var main_scene = get_tree().current_scene
	game_settings = main_scene.get_node_or_null("GameSettings")
	
	if game_settings:
		# Apply any relevant settings from GameSettings
		debug_mode = game_settings.debug_mode
		debug_print("Connected to GameSettings")

func _load_label_scenes() -> void:
	# Load label scenes
	var entity_label_path = "res://scenes/ui/labels/entity_label.tscn"
	var floating_number_path = "res://scenes/ui/labels/floating_number.tscn"
	var world_message_path = "res://scenes/ui/labels/world_message.tscn"
	
	if ResourceLoader.exists(entity_label_path):
		entity_label_scene = load(entity_label_path)
	else:
		# Fallback to creating the scenes dynamically
		debug_print("Entity label scene not found, using dynamic creation")
		entity_label_scene = _create_entity_label_scene()
	
	if ResourceLoader.exists(floating_number_path):
		floating_number_scene = load(floating_number_path)
	else:
		debug_print("Floating number scene not found, using dynamic creation")
		floating_number_scene = _create_floating_number_scene()
	
	if ResourceLoader.exists(world_message_path):
		world_message_scene = load(world_message_path)
	else:
		debug_print("World message scene not found, using dynamic creation")
		world_message_scene = _create_world_message_scene()

# Dynamically create entity label scene if the file doesn't exist
func _create_entity_label_scene() -> PackedScene:
	var scene = PackedScene.new()
	var node = EntityLabel.new()
	node.name = "EntityLabel"
	var script = load("res://scripts/ui/labels/entity_label.gd")
	if script:
		node.set_script(script)
	scene.pack(node)
	return scene

# Dynamically create floating number scene if the file doesn't exist
func _create_floating_number_scene() -> PackedScene:
	var scene = PackedScene.new()
	var node = FloatingNumber.new()
	node.name = "FloatingNumber"
	var script = load("res://scripts/ui/labels/floating_number.gd")
	if script:
		node.set_script(script)
	scene.pack(node)
	return scene

# Dynamically create world message scene if the file doesn't exist
func _create_world_message_scene() -> PackedScene:
	var scene = PackedScene.new()
	var node = WorldMessage.new()
	node.name = "WorldMessage"
	var script = load("res://scripts/ui/labels/world_message.gd")
	if script:
		node.set_script(script)
	scene.pack(node)
	return scene

# Create a container node for all labels
func _create_label_container() -> void:
	# Check if the label container already exists
	var canvas_layer = get_node_or_null("LabelContainer")
	if not canvas_layer:
		canvas_layer = CanvasLayer.new()
		canvas_layer.name = "LabelContainer"
		canvas_layer.layer = 10  # Put labels in front of game elements
		add_child(canvas_layer)
		
		var control = Control.new()
		control.name = "Labels"
		control.anchor_right = 1.0
		control.anchor_bottom = 1.0
		canvas_layer.add_child(control)

func _initialize_label_pools() -> void:
	# Initialize entity label pool
	for i in range(entity_label_pool_size):
		var label = _create_entity_label()
		if label:
			_entity_label_pool.append(label)
	
	# Initialize floating number pool
	for i in range(floating_number_pool_size):
		var label = _create_floating_number()
		if label:
			_floating_number_pool.append(label)
	
	# Initialize world message pool
	for i in range(world_message_pool_size):
		var label = _create_world_message()
		if label:
			_world_message_pool.append(label)
	
	debug_print("Label pools initialized: " + 
				"Entity Labels: " + str(_entity_label_pool.size()) + ", " +
				"Floating Numbers: " + str(_floating_number_pool.size()) + ", " +
				"World Messages: " + str(_world_message_pool.size()))

# Create an entity label
func _create_entity_label() -> Node:
	if entity_label_scene:
		var label = entity_label_scene.instantiate()
		if label:
			label.visible = false
			get_label_container().add_child(label)
			return label
	return null

# Create a floating number
func _create_floating_number() -> Node:
	if floating_number_scene:
		var label = floating_number_scene.instantiate()
		if label:
			label.visible = false
			get_label_container().add_child(label)
			return label
	return null

# Create a world message
func _create_world_message() -> Node:
	if world_message_scene:
		var label = world_message_scene.instantiate()
		if label:
			label.visible = false
			get_label_container().add_child(label)
			return label
	return null

# Get the label container
func get_label_container() -> Control:
	return get_node("LabelContainer/Labels")

# Process function for updating labels
func _process(delta: float) -> void:
	# Update camera reference if needed
	if not _camera or not is_instance_valid(_camera):
		_find_camera()
	
	# Check for viewport resize
	var current_viewport_size = get_viewport().get_visible_rect().size
	if current_viewport_size != _viewport_size:
		_viewport_size = current_viewport_size
		_on_viewport_resize()
	
	# Process entity label visibility at intervals
	_entity_label_check_time += delta
	if _entity_label_check_time >= ENTITY_LABEL_CHECK_INTERVAL:
		_entity_label_check_time = 0
		_update_entity_label_visibility()
	
	# Process world message queue
	_process_message_queue()

# Find the camera in the scene
func _find_camera() -> void:
	# Try to find the camera through the viewport
	_camera = get_viewport().get_camera_2d()
	
	if not _camera:
		# Try finding through player
		var player_ships = get_tree().get_nodes_in_group("player")
		if not player_ships.is_empty():
			_camera = player_ships[0].get_viewport().get_camera_2d()
	
	if not _camera:
		# Try finding in the Main scene
		var main = get_node_or_null("/root/Main")
		if main:
			_camera = main.get_node_or_null("Camera2D")

# Handle viewport resize
func _on_viewport_resize() -> void:
	# Update any layout-dependent elements
	for label in _world_message_pool:
		if label.has_method("on_viewport_resize"):
			label.on_viewport_resize(_viewport_size)

# Update visibility of entity labels based on distance
func _update_entity_label_visibility() -> void:
	if not show_entity_labels or not _camera:
		return
	
	var player_pos = Vector2.ZERO
	if has_node("/root/EntityManager"):
		var player = EntityManager.get_nearest_entity(Vector2.ZERO, "player")
		if player and is_instance_valid(player):
			player_pos = player.global_position
	
	# Get camera view rectangle
	var camera_rect = Rect2(
		_camera.get_screen_center_position() - _viewport_size / (2 * _camera.zoom),
		_viewport_size / _camera.zoom
	)
	camera_rect = camera_rect.grow(200)  # Add some margin
	
	# Update each entity label
	for entity_id in _labeled_entities:
		var label = _labeled_entities[entity_id]
		var entity = null
		
		# Get the entity from EntityManager if available
		if has_node("/root/EntityManager"):
			# Find entity based on ID from various entity dictionaries
			if EntityManager.players.has(entity_id):
				entity = EntityManager.players[entity_id]
			elif EntityManager.ships.has(entity_id):
				entity = EntityManager.ships[entity_id]
			elif EntityManager.asteroids.has(entity_id):
				entity = EntityManager.asteroids[entity_id]
			elif EntityManager.stations.has(entity_id):
				entity = EntityManager.stations[entity_id]
		
		if is_instance_valid(entity):
			# Check distance
			var distance = entity.global_position.distance_to(player_pos)
			
			# Update label position
			label.update_position(entity.global_position)
			
			# Check if in view and not too far
			var in_view = camera_rect.has_point(entity.global_position)
			var in_range = distance <= max_visible_distance
			
			# Update visibility
			label.visible = show_entity_labels and in_view and in_range
		else:
			# Entity no longer valid, remove label
			remove_entity_label(entity_id)

# Process the world message queue
func _process_message_queue() -> void:
	if not show_world_messages or _message_queue.is_empty():
		return
	
	# If no current message or the current message is done
	if not _current_world_message or not _current_world_message.visible:
		# Get the next message from queue
		var message_data = _message_queue.pop_front()
		if message_data:
			_show_next_world_message(message_data)

# Show the next world message in the queue
func _show_next_world_message(message_data: Dictionary) -> void:
	# Get a world message from the pool
	_current_world_message = get_world_message(
		message_data.text,
		message_data.duration,
		message_data.type,
		message_data.position
	)

# Entity event handlers
func _on_entity_spawned(entity: Node, entity_type: String) -> void:
	if not show_entity_labels:
		return
	
	# Only create labels for certain entity types
	if entity_type in ["planet", "station"]:
		# Get entity ID
		var entity_id = -1
		if entity.has_meta("entity_id"):
			entity_id = entity.get_meta("entity_id")
		else:
			return
		
		# Create label if not already exists
		if not _labeled_entities.has(entity_id):
			var entity_name = _get_entity_name(entity)
			var label = create_entity_label(entity, entity_name, entity_type)
			if label:
				_labeled_entities[entity_id] = label
				debug_print("Created label for " + entity_type + ": " + entity_name)

func _on_entity_despawned(entity: Node, _entity_type: String) -> void:
	if entity.has_meta("entity_id"):
		var entity_id = entity.get_meta("entity_id")
		remove_entity_label(entity_id)

# Get entity name for label display
func _get_entity_name(entity: Node) -> String:
	var entity_name = "Unknown"
	
	# Try to get name from various properties
	if entity.has_method("get_entity_name"):
		entity_name = entity.get_entity_name()
	elif entity.has_method("get_planet_name"):
		entity_name = entity.get_planet_name()
	elif entity.has_method("get_station_name"):
		entity_name = entity.get_station_name()
	elif entity.has_property("planet_name"):
		entity_name = entity.planet_name
	elif entity.has_property("moon_name"):
		entity_name = entity.moon_name
	elif entity.has_property("station_name"):
		entity_name = entity.station_name
	else:
		# Use node name as fallback
		entity_name = entity.name
	
	return entity_name

# Event handlers for player and entities
func _on_player_damaged(amount: float, source = null) -> void:
	if not show_damage_numbers:
		return
	
	# Get player position
	var player_ships = get_tree().get_nodes_in_group("player")
	if player_ships.is_empty():
		return
	
	var player = player_ships[0]
	if not is_instance_valid(player):
		return
	
	# Show damage number on player
	create_floating_number(player.global_position, amount, "damage")

func _on_enemy_destroyed(enemy, _destroyer) -> void:
	if is_instance_valid(enemy):
		# Get score/points value if available
		var value = 100  # Default value
		if enemy.has_method("get_score_value"):
			value = enemy.get_score_value()
		elif enemy.has_property("score_value"):
			value = enemy.score_value
		
		# Show score number
		create_floating_number(enemy.global_position, value, "score")

func _on_resource_collected(resource_id: int, amount: int) -> void:
	# Get player position
	var player_ships = get_tree().get_nodes_in_group("player")
	if player_ships.is_empty():
		return
		
	var player = player_ships[0]
	if not is_instance_valid(player):
		return
	
	# Get resource name if ResourceManager is available
	var resource_name = "Resource"
	if has_node("/root/ResourceManager"):
		resource_name = ResourceManager.get_resource_name(resource_id)
	
	# Create floating number for resource
	create_floating_number(
		player.global_position, 
		amount, 
		"resource", 
		{
			"resource_name": resource_name,
			"resource_id": resource_id
		}
	)
	
	# Show world message for significant resource
	if amount > 25:
		show_world_message(
			resource_name + " x" + str(amount) + " collected!",
			2.0, 
			"resource"
		)

# Public API for creating labels

# Create or reuse an entity label
func create_entity_label(entity: Node, label_text: String, entity_type: String = "entity") -> Node:
	if not show_entity_labels:
		return null
	
	# Get a label from the pool
	var label = _get_entity_label_from_pool()
	if not label:
		debug_print("Warning: Entity label pool exhausted")
		return null
	
	# Set up the label
	if label.has_method("setup"):
		label.setup(entity, label_text, entity_type)
		label.visible = true
		return label
	
	return null

# Create or reuse a floating number
func create_floating_number(position: Vector2, value: float, type: String = "default", metadata = null) -> Node:
	if not show_damage_numbers:
		return null
	
	# Get a floating number from the pool
	var label = _get_floating_number_from_pool()
	if not label:
		debug_print("Warning: Floating number pool exhausted")
		return null
	
	# Configure the floating number
	if label.has_method("setup"):
		label.setup(position, value, type, metadata)
		label.visible = true
		return label
	
	return null

# Queue a world message to be shown
func show_world_message(message: String, duration: float = 3.0, type: String = "default", position: String = "center") -> void:
	if not show_world_messages:
		return
	
	# Add to queue
	_message_queue.append({
		"text": message,
		"duration": duration,
		"type": type,
		"position": position
	})
	
	# Process immediately if no current message
	if not _current_world_message or not _current_world_message.visible:
		_process_message_queue()

# Get a world message label directly (used internally by queue processor)
func get_world_message(message: String, duration: float = 3.0, type: String = "default", position: String = "center") -> Node:
	# Get world message from pool
	var label = _get_world_message_from_pool()
	if not label:
		debug_print("Warning: World message pool exhausted")
		return null
	
	# Configure the world message
	if label.has_method("setup"):
		label.setup(message, duration, type, position, _viewport_size)
		label.visible = true
		return label
	
	return null

# Remove an entity label by ID
func remove_entity_label(entity_id: int) -> void:
	if _labeled_entities.has(entity_id):
		var label = _labeled_entities[entity_id]
		if is_instance_valid(label):
			# Return to pool
			if label.has_method("clear"):
				label.clear()
			label.visible = false
		
		_labeled_entities.erase(entity_id)

# Pool management functions

# Get an entity label from the pool
func _get_entity_label_from_pool() -> Node:
	for label in _entity_label_pool:
		if is_instance_valid(label) and not label.visible:
			return label
	
	# If all labels are in use, create a new one if allowed
	if _entity_label_pool.size() < 50:  # Hard cap to prevent excessive labels
		var new_label = _create_entity_label()
		if new_label:
			_entity_label_pool.append(new_label)
			return new_label
	
	return null

# Get a floating number from the pool
func _get_floating_number_from_pool() -> Node:
	for label in _floating_number_pool:
		if is_instance_valid(label) and not label.visible:
			return label
	
	# If all labels are in use, create a new one if allowed
	if _floating_number_pool.size() < 100:  # Hard cap to prevent excessive labels
		var new_label = _create_floating_number()
		if new_label:
			_floating_number_pool.append(new_label)
			return new_label
	
	return null

# Get a world message from the pool
func _get_world_message_from_pool() -> Node:
	for label in _world_message_pool:
		if is_instance_valid(label) and not label.visible:
			return label
	
	# If all labels are in use, create a new one if allowed
	if _world_message_pool.size() < 10:  # Hard cap to prevent excessive labels
		var new_label = _create_world_message()
		if new_label:
			_world_message_pool.append(new_label)
			return new_label
	
	return null

# Debug helpers
func debug_print(message: String) -> void:
	if debug_mode:
		print("[LabelManager] " + message)
