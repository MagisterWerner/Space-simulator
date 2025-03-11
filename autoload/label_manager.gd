extends Node

# Configuration properties
@export var show_damage_numbers = true
@export var show_entity_labels = true
@export var show_world_messages = true
@export var label_scale = 1.0
@export var max_visible_distance = 5000.0

@export var entity_label_pool_size = 20
@export var floating_number_pool_size = 50
@export var world_message_pool_size = 5

@export var debug_mode = false

# References
var game_settings = null
var _label_pools = {
	"entity": [],
	"number": [],
	"message": []
}
var _labeled_entities = {}
var _camera = null
var _viewport_size = Vector2.ZERO

# Scenes
var entity_label_scene = null
var floating_number_scene = null
var world_message_scene = null

# Message queue
var _message_queue = []
var _current_world_message = null

# Entity label timeout
var _entity_label_check_time = 0.0
const ENTITY_LABEL_CHECK_INTERVAL = 0.5

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Find GameSettings
	_find_game_settings()
	
	# Get viewport size
	_viewport_size = get_viewport().get_visible_rect().size
	
	# Initialize resources
	_load_label_scenes()
	_create_label_container()
	_initialize_label_pools()
	
	# Connect to signals
	_connect_signals()

func _find_game_settings():
	var main_scene = get_tree().current_scene
	game_settings = main_scene.get_node_or_null("GameSettings")
	
	if game_settings:
		debug_mode = game_settings.debug_mode

func _load_label_scenes():
	# Load label scenes
	var entity_label_path = "res://scenes/ui/labels/entity_label.tscn"
	var floating_number_path = "res://scenes/ui/labels/floating_number.tscn"
	var world_message_path = "res://scenes/ui/labels/world_message.tscn"
	
	if ResourceLoader.exists(entity_label_path):
		entity_label_scene = load(entity_label_path)
	else:
		entity_label_scene = _create_fallback_scene("EntityLabel")
	
	if ResourceLoader.exists(floating_number_path):
		floating_number_scene = load(floating_number_path)
	else:
		floating_number_scene = _create_fallback_scene("FloatingNumber")
	
	if ResourceLoader.exists(world_message_path):
		world_message_scene = load(world_message_path)
	else:
		world_message_scene = _create_fallback_scene("WorldMessage")

# Create a fallback scene for when the original scene doesn't exist
func _create_fallback_scene(node_name):
	var scene = PackedScene.new()
	var node
	
	# Create appropriate node type based on name
	if node_name == "WorldMessage":
		node = Control.new()
	else:
		node = Node2D.new()
	
	node.name = node_name
	
	# Try to load the script without using class_name
	var script_path = "res://scripts/ui/labels/" + node_name.to_lower() + ".gd"
	if ResourceLoader.exists(script_path):
		node.set_script(load(script_path))
	
	var packed_scene = PackedScene.new()
	packed_scene.pack(node)
	return packed_scene

func _create_label_container():
	var canvas_layer = get_node_or_null("LabelContainer")
	if not canvas_layer:
		canvas_layer = CanvasLayer.new()
		canvas_layer.name = "LabelContainer"
		canvas_layer.layer = 10
		add_child(canvas_layer)
		
		var control = Control.new()
		control.name = "Labels"
		control.anchor_right = 1.0
		control.anchor_bottom = 1.0
		canvas_layer.add_child(control)

func _initialize_label_pools():
	# Create entity labels
	for i in range(entity_label_pool_size):
		var label = _create_label_instance("entity")
		if label:
			_label_pools.entity.append(label)
	
	# Create floating numbers
	for i in range(floating_number_pool_size):
		var label = _create_label_instance("number")
		if label:
			_label_pools.number.append(label)
	
	# Create world messages
	for i in range(world_message_pool_size):
		var label = _create_label_instance("message")
		if label:
			_label_pools.message.append(label)

# Create a label instance based on type
func _create_label_instance(type):
	var scene
	
	match type:
		"entity":
			scene = entity_label_scene
		"number":
			scene = floating_number_scene
		"message":
			scene = world_message_scene
		_:
			return null
	
	if scene:
		var label = scene.instantiate()
		if label:
			label.visible = false
			get_label_container().add_child(label)
			return label
	
	return null

func _connect_signals():
	# Connect to EntityManager
	if has_node("/root/EntityManager"):
		EntityManager.entity_spawned.connect(_on_entity_spawned)
		EntityManager.entity_despawned.connect(_on_entity_despawned)
	
	# Connect to EventManager
	if has_node("/root/EventManager"):
		EventManager.safe_connect("player_damaged", _on_player_damaged)
		EventManager.safe_connect("enemy_destroyed", _on_enemy_destroyed)
		EventManager.safe_connect("resource_collected", _on_resource_collected)

# Get the label container
func get_label_container():
	return get_node("LabelContainer/Labels")

func _process(delta):
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

func _find_camera():
	# Try viewport camera
	_camera = get_viewport().get_camera_2d()
	
	if not _camera:
		# Try player camera
		var player_ships = get_tree().get_nodes_in_group("player")
		if not player_ships.is_empty():
			_camera = player_ships[0].get_viewport().get_camera_2d()
	
	if not _camera:
		# Try main scene camera
		var main = get_node_or_null("/root/Main")
		if main:
			_camera = main.get_node_or_null("Camera2D")

func _on_viewport_resize():
	# Update world messages
	for label in _label_pools.message:
		if label.has_method("on_viewport_resize"):
			label.on_viewport_resize(_viewport_size)

func _update_entity_label_visibility():
	if not show_entity_labels or not _camera:
		return
	
	var player_pos = Vector2.ZERO
	var player = get_nearest_player()
	if player and is_instance_valid(player):
		player_pos = player.global_position
	
	# Get camera view rectangle with margin
	var camera_rect = Rect2(
		_camera.get_screen_center_position() - _viewport_size / (2 * _camera.zoom),
		_viewport_size / _camera.zoom
	).grow(200)
	
	# Update each entity label
	for entity_id in _labeled_entities:
		var label = _labeled_entities[entity_id]
		var entity = _find_entity_by_id(entity_id)
		
		if is_instance_valid(entity):
			var distance = entity.global_position.distance_to(player_pos)
			label.update_position(entity.global_position)
			
			var in_view = camera_rect.has_point(entity.global_position)
			var in_range = distance <= max_visible_distance
			
			label.visible = show_entity_labels and in_view and in_range
		else:
			# Entity no longer valid
			remove_entity_label(entity_id)

func _process_message_queue():
	if not show_world_messages or _message_queue.is_empty():
		return
	
	if not _current_world_message or not _current_world_message.visible:
		var message_data = _message_queue.pop_front()
		if message_data:
			_show_next_world_message(message_data)

func _show_next_world_message(message_data):
	_current_world_message = get_world_message(
		message_data.text,
		message_data.duration,
		message_data.type,
		message_data.position
	)

# Helper functions
func _find_entity_by_id(entity_id):
	if has_node("/root/EntityManager"):
		# Check all entity dictionaries
		for entity_type in EntityManager.entities:
			if EntityManager.entities[entity_type].has(entity_id):
				return EntityManager.entities[entity_type][entity_id]
	return null

func get_nearest_player():
	if has_node("/root/EntityManager"):
		return EntityManager.get_nearest_entity(Vector2.ZERO, "player")
	else:
		var players = get_tree().get_nodes_in_group("player")
		if not players.is_empty():
			return players[0]
	return null

# Entity events
func _on_entity_spawned(entity, entity_type):
	if not show_entity_labels:
		return
	
	if entity_type in ["planet", "station"]:
		var entity_id = -1
		if entity.has_meta("entity_id"):
			entity_id = entity.get_meta("entity_id")
		else:
			return
		
		if not _labeled_entities.has(entity_id):
			var entity_name = _get_entity_name(entity)
			var label = create_entity_label(entity, entity_name, entity_type)
			if label:
				_labeled_entities[entity_id] = label

func _on_entity_despawned(entity, _entity_type):
	if entity.has_meta("entity_id"):
		var entity_id = entity.get_meta("entity_id")
		remove_entity_label(entity_id)

func _get_entity_name(entity):
	# Try various methods to get name
	if entity.has_method("get_entity_name"):
		return entity.get_entity_name()
	elif entity.has_method("get_planet_name"):
		return entity.get_planet_name()
	elif entity.has_method("get_station_name"):
		return entity.get_station_name()
	elif entity.get("planet_name") != null:
		return entity.get("planet_name")
	elif entity.get("station_name") != null:
		return entity.get("station_name")
	else:
		return entity.name

# Event handlers
func _on_player_damaged(amount, source = null):
	if not show_damage_numbers:
		return
	
	var player = get_nearest_player()
	if not player or not is_instance_valid(player):
		return
	
	create_floating_number(player.global_position, amount, "damage")

func _on_enemy_destroyed(enemy, _destroyer):
	if not is_instance_valid(enemy):
		return
		
	var value = 100  # Default value
	if enemy.has_method("get_score_value"):
		value = enemy.get_score_value()
	elif enemy.get("score_value") != null:
		value = enemy.get("score_value")
	
	create_floating_number(enemy.global_position, value, "score")

func _on_resource_collected(resource_id, amount):
	var player = get_nearest_player()
	if not player or not is_instance_valid(player):
		return
	
	var resource_name = "Resource"
	if has_node("/root/ResourceManager"):
		resource_name = ResourceManager.get_resource_name(resource_id)
	
	create_floating_number(
		player.global_position, 
		amount, 
		"resource", 
		{
			"resource_name": resource_name,
			"resource_id": resource_id
		}
	)
	
	if amount > 25:
		show_world_message(
			resource_name + " x" + str(amount) + " collected!",
			2.0, 
			"resource"
		)

# Public API
func create_entity_label(entity, label_text, entity_type = "entity"):
	if not show_entity_labels:
		return null
	
	var label = _get_from_pool("entity")
	if label and label.has_method("setup"):
		label.setup(entity, label_text, entity_type)
		label.visible = true
		return label
	
	return null

func create_floating_number(position, value, type = "default", metadata = null):
	if not show_damage_numbers:
		return null
	
	var label = _get_from_pool("number")
	if label and label.has_method("setup"):
		label.setup(position, value, type, metadata)
		label.visible = true
		return label
	
	return null

func show_world_message(message, duration = 3.0, type = "default", position = "center"):
	if not show_world_messages:
		return
	
	_message_queue.append({
		"text": message,
		"duration": duration,
		"type": type,
		"position": position
	})
	
	if not _current_world_message or not _current_world_message.visible:
		_process_message_queue()

func get_world_message(message, duration = 3.0, type = "default", position = "center"):
	var label = _get_from_pool("message")
	if label and label.has_method("setup"):
		label.setup(message, duration, type, position, _viewport_size)
		label.visible = true
		return label
	
	return null

func remove_entity_label(entity_id):
	if _labeled_entities.has(entity_id):
		var label = _labeled_entities[entity_id]
		if is_instance_valid(label):
			if label.has_method("clear"):
				label.clear()
			label.visible = false
		
		_labeled_entities.erase(entity_id)

# Pool management - optimized
func _get_from_pool(pool_type):
	var pool = _label_pools[pool_type]
	
	# First try to find an inactive label
	for label in pool:
		if is_instance_valid(label) and not label.visible:
			return label
	
	# Create a new one if needed
	var max_size = 50 if pool_type == "entity" else (100 if pool_type == "number" else 10)
	
	if pool.size() < max_size:
		var new_label = _create_label_instance(pool_type)
		if new_label:
			pool.append(new_label)
			return new_label
	
	# If at max capacity, reuse oldest
	return pool[0] if not pool.is_empty() else null

# Debug helper
func debug_print(message):
	if debug_mode:
		print("[LabelManager] " + message)
