extends Node

# Configuration properties
@export var show_damage_numbers: bool = true
@export var show_entity_labels: bool = true
@export var show_world_messages: bool = true
@export var label_scale: float = 1.0
@export var max_visible_distance: float = 5000.0

# Pool sizing
@export var entity_label_pool_size: int = 20
@export var floating_number_pool_size: int = 50
@export var world_message_pool_size: int = 5

# Debug
@export var debug_mode: bool = false

# Label pools - optimized data structures
var _label_pools = {
	"entity": [],
	"number": [],
	"message": []
}

# Active label tracking - optimized with dictionaries
var _active_labels = {
	"entity": {},
	"number": {},
	"message": {}
}

# Label scenes - cached
var _label_scenes = {
	"entity": null,
	"number": null,
	"message": null
}

# References
var game_settings = null
var _camera = null
var _viewport_size = Vector2.ZERO
var _entity_manager = null
var _event_manager = null
var _resource_manager = null

# Update timers for throttling
var _entity_label_check_time: float = 0.0
const ENTITY_LABEL_CHECK_INTERVAL = 0.5

# Message processing
var _message_queue = []
var _current_world_message = null

# Camera frustum for culling
var _camera_rect = Rect2()
var _camera_zoom = Vector2.ONE
var _culling_enabled = true

# Cached player position for distance checks
var _cached_player_pos = Vector2.ZERO
var _player_pos_update_time: float = 0.0
const PLAYER_POS_UPDATE_INTERVAL = 0.2

# Scene paths - used only during initialization
const ENTITY_LABEL_PATH = "res://scenes/ui/labels/entity_label.tscn"
const FLOATING_NUMBER_PATH = "res://scenes/ui/labels/floating_number.tscn"
const WORLD_MESSAGE_PATH = "res://scenes/ui/labels/world_message.tscn"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	_find_game_settings()
	_initialize_resources()
	_connect_signals()

func _initialize_resources() -> void:
	# Create label container
	_create_label_container()
	
	# Get viewport size
	_viewport_size = get_viewport().get_visible_rect().size
	
	# Load label scenes
	_load_label_scenes()
	
	# Initialize label pools
	_initialize_label_pools()
	
	# Find entity manager
	_entity_manager = get_node_or_null("/root/EntityManager")
	_event_manager = get_node_or_null("/root/EventManager")
	_resource_manager = get_node_or_null("/root/ResourceManager")

func _find_game_settings() -> void:
	var main_scene = get_tree().current_scene
	game_settings = main_scene.get_node_or_null("GameSettings")
	
	if game_settings:
		debug_mode = game_settings.debug_mode and game_settings.debug_ui
		
		# Connect to debug settings changes
		if game_settings.has_signal("debug_settings_changed") and not game_settings.is_connected("debug_settings_changed", _on_debug_settings_changed):
			game_settings.connect("debug_settings_changed", _on_debug_settings_changed)

func _on_debug_settings_changed(debug_settings: Dictionary) -> void:
	debug_mode = debug_settings.get("master", false) and debug_settings.get("ui", false)

func _load_label_scenes() -> void:
	# Load and cache scenes efficiently
	_label_scenes.entity = _load_scene_or_fallback(ENTITY_LABEL_PATH, "EntityLabel")
	_label_scenes.number = _load_scene_or_fallback(FLOATING_NUMBER_PATH, "FloatingNumber")
	_label_scenes.message = _load_scene_or_fallback(WORLD_MESSAGE_PATH, "WorldMessage")

func _load_scene_or_fallback(path: String, node_name: String) -> PackedScene:
	if ResourceLoader.exists(path):
		return load(path)
	else:
		# Create fallback scene
		return _create_fallback_scene(node_name)

func _create_fallback_scene(node_name: String) -> PackedScene:
	var node
	
	# Create appropriate node type based on name
	if node_name == "WorldMessage":
		node = Control.new()
	else:
		node = Node2D.new()
	
	node.name = node_name
	
	# Try to load the script
	var script_path = "res://scripts/ui/labels/" + node_name.to_lower() + ".gd"
	if ResourceLoader.exists(script_path):
		node.set_script(load(script_path))
	
	var packed_scene = PackedScene.new()
	packed_scene.pack(node)
	return packed_scene

func _create_label_container() -> void:
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

func _initialize_label_pools() -> void:
	# Create entity labels
	for i in range(entity_label_pool_size):
		_create_and_add_label("entity")
	
	# Create floating numbers
	for i in range(floating_number_pool_size):
		_create_and_add_label("number")
	
	# Create world messages
	for i in range(world_message_pool_size):
		_create_and_add_label("message")

func _create_and_add_label(type: String) -> void:
	var label = _create_label_instance(type)
	if label:
		_label_pools[type].append(label)

func _create_label_instance(type: String) -> Node:
	if not _label_scenes.has(type) or not _label_scenes[type]:
		return null
	
	var label = _label_scenes[type].instantiate()
	if label:
		label.visible = false
		get_label_container().add_child(label)
		return label
	
	return null

func _connect_signals() -> void:
	# Connect to EntityManager
	if _entity_manager:
		if _entity_manager.has_signal("entity_spawned") and not _entity_manager.is_connected("entity_spawned", _on_entity_spawned):
			_entity_manager.connect("entity_spawned", _on_entity_spawned)
		
		if _entity_manager.has_signal("entity_despawned") and not _entity_manager.is_connected("entity_despawned", _on_entity_despawned):
			_entity_manager.connect("entity_despawned", _on_entity_despawned)
	
	# Connect to EventManager
	if _event_manager:
		_event_manager.safe_connect("player_damaged", _on_player_damaged)
		_event_manager.safe_connect("enemy_destroyed", _on_enemy_destroyed)
		_event_manager.safe_connect("resource_collected", _on_resource_collected)

func get_label_container() -> Control:
	return get_node("LabelContainer/Labels")

func _process(delta: float) -> void:
	# Update camera reference if needed
	if not _camera or not is_instance_valid(_camera):
		_find_camera()
		if not _camera:
			return
	
	# Check for viewport resize - less frequently
	var current_viewport_size = get_viewport().get_visible_rect().size
	if current_viewport_size != _viewport_size:
		_viewport_size = current_viewport_size
		_on_viewport_resize()
	
	# Update camera frustum for culling
	_update_camera_frustum()
	
	# Process entity labels at intervals
	_entity_label_check_time += delta
	if _entity_label_check_time >= ENTITY_LABEL_CHECK_INTERVAL:
		_entity_label_check_time = 0
		_update_entity_label_visibility()
		
		# Update player position cache at the same time
		_update_player_position_cache()
	
	# Process world message queue
	_process_message_queue()

func _find_camera() -> void:
	# Try viewport camera first - most efficient path
	_camera = get_viewport().get_camera_2d()
	
	if not _camera:
		# Try player's camera
		var player = _get_player()
		if player:
			_camera = player.get_viewport().get_camera_2d()
	
	if not _camera:
		# Last resort - look in main scene
		var main = get_node_or_null("/root/Main")
		if main:
			_camera = main.get_node_or_null("Camera2D")

func _on_viewport_resize() -> void:
	# Update world messages for new viewport size
	for label in _label_pools.message:
		if label.has_method("on_viewport_resize"):
			label.on_viewport_resize(_viewport_size)

func _update_camera_frustum() -> void:
	if not _camera or not is_instance_valid(_camera):
		return
		
	if _camera.zoom == _camera_zoom:
		return  # No change in zoom, skip update
		
	_camera_zoom = _camera.zoom
	
	# Calculate camera view rectangle with margin for culling
	var camera_center = _camera.get_screen_center_position()
	var visible_rect_size = _viewport_size / _camera_zoom
	_camera_rect = Rect2(
		camera_center - visible_rect_size / 2,
		visible_rect_size
	).grow(100)  # Add margin for smoother transitions

func _update_entity_label_visibility() -> void:
	if not show_entity_labels or not _camera:
		return
		
	var player_pos = _get_cached_player_position()
	
	# Only process active entity labels
	for entity_id in _active_labels.entity:
		var label = _active_labels.entity[entity_id]
		if not is_instance_valid(label):
			_active_labels.entity.erase(entity_id)
			continue
			
		var entity = _get_entity_by_id(entity_id)
		
		if is_instance_valid(entity) and entity is Node2D:
			# Update position
			label.update_position(entity.global_position)
			
			# Only set visibility if camera is available
			if _culling_enabled and _camera and is_instance_valid(_camera):
				var in_camera_view = _camera_rect.has_point(entity.global_position)
				var distance_factor = 1.0
				
				# Apply distance fading if player position is available
				if player_pos != Vector2.ZERO:
					var distance = entity.global_position.distance_to(player_pos)
					if distance > max_visible_distance:
						label.visible = false
						continue
					
					distance_factor = 1.0 - (distance / max_visible_distance)
				
				# Set visibility
				label.visible = show_entity_labels and in_camera_view
				
				# Apply distance fade
				if label.visible and label.has_method("set_distance_fade"):
					label.set_distance_fade(distance_factor)
		else:
			# Entity no longer valid
			remove_entity_label(entity_id)

func _process_message_queue() -> void:
	if not show_world_messages or _message_queue.is_empty():
		return
	
	if not _current_world_message or not _current_world_message.visible:
		var message_data = _message_queue.pop_front()
		if message_data:
			_show_next_world_message(message_data)

func _show_next_world_message(message_data: Dictionary) -> void:
	_current_world_message = get_world_message(
		message_data.text,
		message_data.duration,
		message_data.type,
		message_data.position
	)

# Helper functions
func _get_entity_by_id(entity_id: int) -> Node:
	if _entity_manager and _entity_manager.has_method("get_entity_by_id"):
		return _entity_manager.get_entity_by_id(entity_id)
	
	return null

func _get_player() -> Node:
	if _entity_manager and _entity_manager.has_method("get_nearest_entity"):
		return _entity_manager.get_nearest_entity(Vector2.ZERO, "player")
	else:
		var players = get_tree().get_nodes_in_group("player")
		if not players.is_empty():
			return players[0]
	return null

func _update_player_position_cache() -> void:
	var player = _get_player()
	if player and is_instance_valid(player) and player is Node2D:
		_cached_player_pos = player.global_position
		_player_pos_update_time = Time.get_ticks_msec() / 1000.0

func _get_cached_player_position() -> Vector2:
	var current_time = Time.get_ticks_msec() / 1000.0
	
	if current_time - _player_pos_update_time > PLAYER_POS_UPDATE_INTERVAL:
		_update_player_position_cache()
	
	return _cached_player_pos

# Entity events
func _on_entity_spawned(entity: Node, entity_type: String) -> void:
	if not show_entity_labels:
		return
	
	# Only create labels for planets and stations
	if entity_type in ["planet", "station"]:
		var entity_id = -1
		if entity.has_meta("entity_id"):
			entity_id = entity.get_meta("entity_id")
		else:
			return
		
		if not _active_labels.entity.has(entity_id):
			var entity_name = _get_entity_name(entity)
			var label = create_entity_label(entity, entity_name, entity_type)
			if label:
				_active_labels.entity[entity_id] = label

func _on_entity_despawned(entity: Node, _entity_type: String) -> void:
	if entity.has_meta("entity_id"):
		var entity_id = entity.get_meta("entity_id")
		remove_entity_label(entity_id)

func _get_entity_name(entity: Node) -> String:
	# Try various methods to get name - most efficient checks first
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
func _on_player_damaged(amount: float, source = null) -> void:
	if not show_damage_numbers:
		return
	
	var player = _get_player()
	if not player or not is_instance_valid(player) or not player is Node2D:
		return
	
	create_floating_number(player.global_position, amount, "damage")

func _on_enemy_destroyed(enemy, _destroyer) -> void:
	if not is_instance_valid(enemy) or not enemy is Node2D:
		return
		
	var value = 100  # Default value
	if enemy.has_method("get_score_value"):
		value = enemy.get_score_value()
	elif enemy.get("score_value") != null:
		value = enemy.get("score_value")
	
	create_floating_number(enemy.global_position, value, "score")

func _on_resource_collected(resource_id, amount) -> void:
	var player = _get_player()
	if not player or not is_instance_valid(player) or not player is Node2D:
		return
	
	var resource_name = "Resource"
	if _resource_manager:
		resource_name = _resource_manager.get_resource_name(resource_id)
	
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
func create_entity_label(entity: Node, label_text: String, entity_type: String = "entity") -> Node:
	if not show_entity_labels:
		return null
	
	var label = _get_from_pool("entity")
	if label and label.has_method("setup"):
		label.setup(entity, label_text, entity_type)
		label.visible = true
		return label
	
	return null

func create_floating_number(position: Vector2, value: float, type: String = "default", metadata = null) -> Node:
	if not show_damage_numbers:
		return null
	
	var label = _get_from_pool("number")
	if label and label.has_method("setup"):
		label.setup(position, value, type, metadata)
		label.visible = true
		return label
	
	return null

func show_world_message(message: String, duration: float = 3.0, type: String = "default", position: String = "center") -> void:
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

func get_world_message(message: String, duration: float = 3.0, type: String = "default", position: String = "center") -> Node:
	var label = _get_from_pool("message")
	if label and label.has_method("setup"):
		label.setup(message, duration, type, position, _viewport_size)
		label.visible = true
		return label
	
	return null

func remove_entity_label(entity_id: int) -> void:
	if _active_labels.entity.has(entity_id):
		var label = _active_labels.entity[entity_id]
		if is_instance_valid(label):
			if label.has_method("clear"):
				label.clear()
			label.visible = false
		
		_active_labels.entity.erase(entity_id)

# Optimized pool management with smarter allocation
func _get_from_pool(pool_type: String) -> Node:
	var pool = _label_pools[pool_type]
	
	# First pass: Try to find an inactive label
	for label in pool:
		if is_instance_valid(label) and not label.visible:
			return label
	
	# If all labels are in use, find the oldest label
	var oldest_label = null
	var oldest_time = INF
	
	for label in pool:
		if is_instance_valid(label) and label.has_meta("created_time"):
			var created_time = label.get_meta("created_time")
			if created_time < oldest_time:
				oldest_time = created_time
				oldest_label = label
	
	if oldest_label:
		if oldest_label.has_method("clear"):
			oldest_label.clear()
		return oldest_label
	
	# If still no label available, create a new one with dynamic pool sizing
	var max_size = 50 if pool_type == "entity" else (100 if pool_type == "number" else 10)
	
	if pool.size() < max_size:
		var new_label = _create_label_instance(pool_type)
		if new_label:
			new_label.set_meta("created_time", Time.get_ticks_msec())
			pool.append(new_label)
			return new_label
	
	# Last resort - return first label in pool
	return pool[0] if not pool.is_empty() else null

# Debug helper
func _debug_print(message: String) -> void:
	if debug_mode:
		print("[LabelManager] " + message)

# Enable or disable culling (for performance testing)
func set_culling_enabled(enabled: bool) -> void:
	_culling_enabled = enabled
