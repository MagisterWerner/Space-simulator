extends Node

# Core signals
signal music_changed(track_name)
signal volume_changed(bus_name, volume_db)
signal music_finished
signal sfx_pool_created(sfx_name, pool_size)
signal audio_buses_initialized

# Label-specific signals
signal label_created(entity, label_type)
signal celestial_name_generated(entity, name, entity_type)

# Configuration properties
@export var show_damage_numbers: bool = true
@export var show_entity_labels: bool = true
@export var show_world_messages: bool = true
@export var label_scale: float = 1.0
@export var max_visible_distance: float = 5000.0

# Celestial body label configuration
@export var show_celestial_labels: bool = true
@export var planet_label_offset: float = -45.0
@export var moon_label_offset: float = -25.0
@export var celestial_label_fade_start: float = 3000.0
@export var celestial_label_max_distance: float = 5000.0

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

# Celestial body labels tracking
var _celestial_labels = {
	"planet": {},  # Keyed by entity_id
	"moon": {}     # Keyed by entity_id
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
var _seed_manager = null  # Reference to SeedManager for deterministic generation

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

# Celestial body style definitions
var _celestial_styles = {
	"planet_terran": {
		"color": Color(0.7, 1.0, 0.7),
		"outline": Color(0.0, 0.3, 0.0, 0.7),
		"size": 18,
		"offset": Vector2(0, -45)
	},
	"planet_gaseous": {
		"color": Color(0.9, 0.9, 0.6),
		"outline": Color(0.4, 0.3, 0.0, 0.7),
		"size": 20,
		"offset": Vector2(0, -55)
	},
	"moon_rocky": {
		"color": Color(0.8, 0.8, 0.8),
		"outline": Color(0.2, 0.2, 0.2, 0.7),
		"size": 14,
		"offset": Vector2(0, -25)
	},
	"moon_icy": {
		"color": Color(0.7, 0.9, 1.0),
		"outline": Color(0.0, 0.2, 0.4, 0.7),
		"size": 14,
		"offset": Vector2(0, -25)
	},
	"moon_volcanic": {
		"color": Color(1.0, 0.6, 0.4),
		"outline": Color(0.4, 0.1, 0.0, 0.7),
		"size": 14,
		"offset": Vector2(0, -25)
	}
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	_find_game_settings()
	_initialize_resources()
	_connect_signals()
	_cache_managers()

func _initialize_resources() -> void:
	# Create label container
	_create_label_container()
	
	# Get viewport size
	_viewport_size = get_viewport().get_visible_rect().size
	
	# Load label scenes
	_load_label_scenes()
	
	# Initialize label pools
	_initialize_label_pools()

func _cache_managers() -> void:
	# Find entity manager
	_entity_manager = get_node_or_null("/root/EntityManager")
	_event_manager = get_node_or_null("/root/EventManager")
	_resource_manager = get_node_or_null("/root/ResourceManager")
	_seed_manager = get_node_or_null("/root/SeedManager")
	
	# Connect to entity spawned events if possible
	if _entity_manager and _entity_manager.has_signal("entity_spawned") and not _entity_manager.is_connected("entity_spawned", _on_entity_spawned):
		_entity_manager.connect("entity_spawned", _on_entity_spawned)
	
	if _event_manager:
		_event_manager.safe_connect("entity_spawned", _on_entity_spawned)

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
	
	# Handle automatic celestial body registration
	if entity_type == "planet":
		register_planet(entity)
	elif entity_type == "moon":
		register_moon(entity)
	
	# Original entity label creation logic for planets and stations
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
		
		# Also remove from celestial tracking if present
		if _celestial_labels.planet.has(entity_id):
			_celestial_labels.planet.erase(entity_id)
		if _celestial_labels.moon.has(entity_id):
			_celestial_labels.moon.erase(entity_id)

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
func _on_player_damaged(amount: float, _source = null) -> void:
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

#
# CELESTIAL BODY LABEL MANAGEMENT
# New methods for planet and moon name generation and display
#

# Register a planet for labeling with name generation
func register_planet(planet: Node2D) -> void:
	if not planet or not is_instance_valid(planet) or not show_celestial_labels:
		return
	
	# Skip if already registered
	if planet.has_meta("entity_id"):
		var entity_id = planet.get_meta("entity_id")
		if _celestial_labels.planet.has(entity_id):
			return
	
	# Determine if planet is gaseous based on class name or properties
	var is_gaseous = false
	if "is_gaseous_planet" in planet:
		is_gaseous = planet.is_gaseous_planet
	elif planet is PlanetGaseous or planet.get_script() and planet.get_script().resource_path.find("gaseous") != -1:
		is_gaseous = true
	
	# Get theme ID
	var theme_id = -1
	if "theme_id" in planet:
		theme_id = planet.theme_id
	
	# Generate planet name if not set
	var planet_name = ""
	if "planet_name" in planet and not planet.planet_name.is_empty():
		planet_name = planet.planet_name
	else:
		# Generate a name based on seed value
		var seed_value = 0
		if "seed_value" in planet:
			seed_value = planet.seed_value
		
		# Use the generator function
		planet_name = _generate_planet_name(seed_value, is_gaseous, theme_id)
		
		# Try to set the planet name property
		if "planet_name" in planet:
			planet.planet_name = planet_name
	
	# Create the label with appropriate style
	var label_type = "planet_gaseous" if is_gaseous else "planet_terran"
	var label = create_entity_label(planet, planet_name, label_type)
	
	# Apply styling if EntityLabel has style support
	if label and label.has_method("set_style"):
		label.set_style(label_type)
	
	# Apply colors if it has that method instead
	elif label and label.has_method("set_colors"):
		var style = _celestial_styles[label_type]
		label.set_colors(style.color, style.outline)
		label.label_offset = style.offset
	
	# Track the label
	if planet.has_meta("entity_id"):
		var entity_id = planet.get_meta("entity_id")
		_celestial_labels.planet[entity_id] = {
			"label": label,
			"planet": planet,
			"name": planet_name
		}
	
	# Connect to planet signals for moon handling
	if planet.has_signal("planet_loaded") and not planet.is_connected("planet_loaded", _on_planet_loaded):
		planet.connect("planet_loaded", _on_planet_loaded)
	
	celestial_name_generated.emit(planet, planet_name, "planet")
	
	if debug_mode:
		print("[LabelManager] Registered planet name: " + planet_name)

# Register a moon for labeling with name generation
func register_moon(moon: Node2D) -> void:
	if not moon or not is_instance_valid(moon) or not show_celestial_labels:
		return
	
	# Skip if already registered
	if moon.has_meta("entity_id"):
		var entity_id = moon.get_meta("entity_id")
		if _celestial_labels.moon.has(entity_id):
			return
	
	# Get moon type
	var moon_type = 0  # Default to rocky
	if "moon_type" in moon:
		moon_type = moon.moon_type
	
	# Get parent planet reference and name
	var parent_planet = null
	var parent_name = "Planet"
	var moon_index = 0
	
	if "parent_planet" in moon:
		parent_planet = moon.parent_planet
		if parent_planet and "planet_name" in parent_planet:
			parent_name = parent_planet.planet_name
		
		# Get moon index
		if parent_planet and "moons" in parent_planet:
			moon_index = parent_planet.moons.find(moon)
			if moon_index < 0:
				moon_index = 0
	
	# Generate moon name if not set
	var moon_name = ""
	if "moon_name" in moon and not moon.moon_name.is_empty():
		moon_name = moon.moon_name
	else:
		# Get seed value
		var seed_value = 0
		if "seed_value" in moon:
			seed_value = moon.seed_value
		
		# Generate name
		moon_name = _generate_moon_name(seed_value, parent_name, moon_type, moon_index)
		
		# Set name property if available
		if "moon_name" in moon:
			moon.moon_name = moon_name
	
	# Determine label style based on moon type
	var label_type = "moon_rocky"  # Default
	match moon_type:
		0: label_type = "moon_rocky"
		1: label_type = "moon_icy"
		2: label_type = "moon_volcanic"
	
	# Create the label
	var label = create_entity_label(moon, moon_name, label_type)
	
	# Apply styling if supported
	if label:
		if label.has_method("set_style"):
			label.set_style(label_type)
		elif label.has_method("set_colors") and _celestial_styles.has(label_type):
			var style = _celestial_styles[label_type]
			label.set_colors(style.color, style.outline)
			label.label_offset = style.offset
	
	# Track the label
	if moon.has_meta("entity_id"):
		var entity_id = moon.get_meta("entity_id")
		_celestial_labels.moon[entity_id] = {
			"label": label,
			"moon": moon,
			"name": moon_name,
			"parent": parent_planet,
			"type": moon_type,
			"index": moon_index
		}
	
	celestial_name_generated.emit(moon, moon_name, "moon")
	
	if debug_mode:
		print("[LabelManager] Registered moon name: " + moon_name)

# Name generation functions that leverage the SeedManager
func _generate_planet_name(seed_value: int, is_gaseous: bool = false, theme_id: int = -1) -> String:
	# Cache key for consistent names
	var cache_key = "planet_%d_%s_%d" % [seed_value, str(is_gaseous), theme_id]
	
	# Use static generator class if available
	if ResourceLoader.exists("res://scripts/generators/planet_name_generator.gd"):
		var PlanetNameGenerator = load("res://scripts/generators/planet_name_generator.gd")
		if PlanetNameGenerator.has_method("generate_planet_name"):
			return PlanetNameGenerator.generate_planet_name(seed_value, is_gaseous, theme_id)
	
	# Fallback implementation using SeedManager
	var style = _get_random_int(seed_value, 0, 2)
	var name = ""
	
	match style:
		0: name = _generate_compound_name(seed_value, is_gaseous)
		1: name = _generate_designation_name(seed_value, is_gaseous)
		2: name = _generate_descriptive_name(seed_value, is_gaseous, theme_id)
	
	return name

func _generate_moon_name(seed_value: int, parent_name: String, moon_type: int, moon_index: int = 0) -> String:
	# Use static generator class if available
	if ResourceLoader.exists("res://scripts/generators/planet_name_generator.gd"):
		var PlanetNameGenerator = load("res://scripts/generators/planet_name_generator.gd")
		if PlanetNameGenerator.has_method("generate_moon_name"):
			return PlanetNameGenerator.generate_moon_name(seed_value, parent_name, moon_type, moon_index)
	
	# Fallback implementation
	var style = _get_random_int(seed_value, 0, 1)
	var name = ""
	
	match style:
		0: name = _generate_moon_compound_name(seed_value)
		1: name = _generate_moon_designation(parent_name, moon_index)
	
	return name

# Handle planets loading their moons
func _on_planet_loaded(planet: Node) -> void:
	# Register moons of this planet
	if not is_instance_valid(planet) or not "moons" in planet:
		return
	
	for moon in planet.moons:
		if is_instance_valid(moon):
			register_moon(moon)

# Name generation helpers
func _generate_compound_name(seed_value: int, is_gaseous: bool) -> String:
	const PLANET_PREFIXES = [
		"Aet", "Aeg", "Aqu", "Ast", "Ath", "Bor", "Cal", "Chro", "Cir", "Cor"
	]
	const PLANET_SUFFIXES = [
		"on", "us", "um", "ux", "ax", "ix", "os", "is", "ia", "ium"
	]
	
	var prefix_index = _get_random_int(seed_value, 0, PLANET_PREFIXES.size() - 1)
	var suffix_index = _get_random_int(seed_value + 1, 0, PLANET_SUFFIXES.size() - 1)
	
	return PLANET_PREFIXES[prefix_index] + PLANET_SUFFIXES[suffix_index]

func _generate_designation_name(seed_value: int, is_gaseous: bool) -> String:
	var prefix_length = _get_random_int(seed_value, 1, 3)
	var number_length = _get_random_int(seed_value + 1, 3, 5)
	
	const LETTERS = "abcdefghijklmnopqrstuvwxyz"
	const NUMBERS = "0123456789"
	
	var prefix = ""
	for i in range(prefix_length):
		var letter_idx = _get_random_int(seed_value + 10 + i, 0, LETTERS.length() - 1)
		prefix += LETTERS[letter_idx].to_upper()
	
	var number = ""
	for i in range(number_length):
		var digit_idx = _get_random_int(seed_value + 20 + i, 0, NUMBERS.length() - 1)
		number += NUMBERS[digit_idx]
	
	return prefix + "-" + number

func _generate_descriptive_name(seed_value: int, is_gaseous: bool, theme_id: int) -> String:
	const TERRAN_DESCRIPTORS = {
		0: ["Arid", "Dusty", "Sandy", "Barren"], # Arid
		1: ["Frozen", "Icy", "Glacial", "Frigid"], # Ice
		2: ["Molten", "Volcanic", "Burning", "Infernal"], # Lava
		3: ["Verdant", "Lush", "Fertile", "Vibrant"], # Lush
		4: ["Desert", "Dune", "Parched", "Desolate"], # Desert
		5: ["Alpine", "Mountainous", "Craggy", "Rugged"], # Alpine
		6: ["Oceanic", "Aquatic", "Abyssal", "Maritime"], # Ocean
		-1: ["Mysterious", "Enigmatic", "Unknown", "Distant"] # Generic
	}
	
	const GAS_DESCRIPTORS = {
		0: ["Colossal", "Mammoth", "Banded", "Massive"], # Jupiter-like
		1: ["Ringed", "Crowned", "Encircled", "Belted"], # Saturn-like
		2: ["Cyan", "Tilted", "Sideways", "Azure"], # Uranus-like
		3: ["Stormy", "Deep", "Cobalt", "Sapphire"], # Neptune-like
		-1: ["Gaseous", "Nebulous", "Swirling", "Cloudy"] # Generic
	}
	
	var descriptor_array = []
	
	if is_gaseous:
		if theme_id >= 8 and GAS_DESCRIPTORS.has(theme_id - 8):
			descriptor_array = GAS_DESCRIPTORS[theme_id - 8]
		else:
			descriptor_array = GAS_DESCRIPTORS[-1]
	else:
		if theme_id >= 0 and theme_id < 7 and TERRAN_DESCRIPTORS.has(theme_id):
			descriptor_array = TERRAN_DESCRIPTORS[theme_id]
		else:
			descriptor_array = TERRAN_DESCRIPTORS[-1]
	
	var descriptor_idx = _get_random_int(seed_value, 0, descriptor_array.size() - 1)
	var descriptor = descriptor_array[descriptor_idx]
	
	return descriptor + " " + _generate_compound_name(seed_value + 100, is_gaseous)

func _generate_moon_compound_name(seed_value: int) -> String:
	const MOON_PREFIXES = [
		"Lun", "Phob", "Deim", "Eur", "Gan", "Call", "Teth", "Rhe", "Tita"
	]
	const MOON_SUFFIXES = [
		"a", "os", "is", "us", "o", "ia", "ius", "on", "ar"
	]
	
	var prefix_index = _get_random_int(seed_value, 0, MOON_PREFIXES.size() - 1)
	var suffix_index = _get_random_int(seed_value + 1, 0, MOON_SUFFIXES.size() - 1)
	
	return MOON_PREFIXES[prefix_index] + MOON_SUFFIXES[suffix_index]

func _generate_moon_designation(parent_name: String, moon_index: int) -> String:
	var parent_initial = ""
	
	if parent_name.length() >= 2:
		parent_initial = parent_name.substr(0, 2).to_upper()
	else:
		parent_initial = parent_name.to_upper()
	
	return parent_initial + "-" + ('I'.repeat(moon_index + 1))

# Helper method for SeedManager integration
func _get_random_int(object_id: int, min_val: int, max_val: int) -> int:
	if _seed_manager and _seed_manager.has_method("get_random_int"):
		return _seed_manager.get_random_int(object_id, min_val, max_val)
	else:
		var rng = RandomNumberGenerator.new()
		rng.seed = object_id
		return rng.randi_range(min_val, max_val)

# Public utilities for celestial labeling
func set_celestial_label_visibility(visible: bool) -> void:
	show_celestial_labels = visible
	
	# Update all existing labels
	for entity_id in _celestial_labels.planet:
		var data = _celestial_labels.planet[entity_id]
		if is_instance_valid(data.label):
			data.label.visible = visible
	
	for entity_id in _celestial_labels.moon:
		var data = _celestial_labels.moon[entity_id]
		if is_instance_valid(data.label):
			data.label.visible = visible

func update_celestial_label_style(theme_id: int, is_gaseous: bool, planet) -> void:
	# Find the entity in our tracking
	var entity_id = -1
	if planet.has_meta("entity_id"):
		entity_id = planet.get_meta("entity_id")
	else:
		return
	
	# Skip if not tracked
	if not _celestial_labels.planet.has(entity_id):
		return
	
	var data = _celestial_labels.planet[entity_id]
	var label = data.label
	
	if not is_instance_valid(label):
		return
	
	# Determine style
	var label_type = "planet_gaseous" if is_gaseous else "planet_terran"
	
	# Apply styling if supported
	if label.has_method("set_style"):
		label.set_style(label_type)
	elif label.has_method("set_colors") and _celestial_styles.has(label_type):
		var style = _celestial_styles[label_type]
		label.set_colors(style.color, style.outline)
		label.label_offset = style.offset
		
	# Update name if needed
	if "planet_name" in planet and not planet.planet_name.is_empty():
		# If the name changed, update the label
		if planet.planet_name != data.name:
			data.name = planet.planet_name
			if label.has_method("set_text"):
				label.set_text(planet.planet_name)
