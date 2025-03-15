# scripts/spawners/entity_spawner_base.gd
extends Node
class_name EntitySpawnerBase

signal entity_spawned(entity, data)
signal spawner_ready

# Scene caching
var _scene_cache = {}
var _spawned_entities = []
var _initialized = false
var _debug_mode = false

# Manager references
var _entity_manager = null
var _audio_manager = null
var _event_manager = null
var _game_settings = null

func _ready() -> void:
	# Add to the spawners group for easy access
	add_to_group("spawners")
	
	# Cache manager references
	_entity_manager = get_node_or_null("/root/EntityManager")
	_audio_manager = get_node_or_null("/root/AudioManager")
	_event_manager = get_node_or_null("/root/EventManager")
	
	# Find game settings
	_game_settings = get_tree().current_scene.get_node_or_null("GameSettings")
	if _game_settings:
		_debug_mode = _game_settings.debug_mode
	
	call_deferred("_initialize")

func _initialize() -> void:
	# Load common scenes
	_load_common_scenes()
	_initialized = true
	spawner_ready.emit()

func _load_common_scenes() -> void:
	# To be implemented by subclasses
	pass

func _load_scene(key: String, path: String) -> void:
	if _scene_cache.has(key):
		return
		
	if not ResourceLoader.exists(path):
		push_error("EntitySpawnerBase: Scene file does not exist: " + path)
		return
		
	_scene_cache[key] = load(path)

# Spawn an entity from data
func spawn_entity(data: EntityData) -> Node:
	# Base implementation, to be overridden
	push_error("EntitySpawnerBase: spawn_entity is a virtual method that should be overridden")
	return null

# Register an entity with the entity manager
func register_entity(entity: Node, entity_type: String, data = null) -> void:
	if _entity_manager and _entity_manager.has_method("register_entity"):
		_entity_manager.register_entity(entity, entity_type)
	
	# Keep track of spawned entities for cleanup
	_spawned_entities.append(entity)
	
	# Emit signal for external systems
	entity_spawned.emit(entity, data)

# Unregister and destroy an entity
func destroy_entity(entity: Node) -> void:
	if not is_instance_valid(entity):
		return
		
	if _entity_manager and _entity_manager.has_method("deregister_entity"):
		_entity_manager.deregister_entity(entity)
	
	if entity in _spawned_entities:
		_spawned_entities.erase(entity)
	
	entity.queue_free()

# Clear all spawned entities
func clear_spawned_entities() -> void:
	var entities_to_clear = _spawned_entities.duplicate()
	for entity in entities_to_clear:
		if is_instance_valid(entity):
			destroy_entity(entity)
	
	_spawned_entities.clear()

# Get cell position in world coordinates
func _get_cell_world_position(cell: Vector2i) -> Vector2:
	if _game_settings and _game_settings.has_method("get_cell_world_position"):
		return _game_settings.get_cell_world_position(cell)
	
	# Fallback if game settings unavailable
	var cell_size = 1024
	var grid_size = 10
	var grid_offset = Vector2(cell_size * grid_size / 2.0, cell_size * grid_size / 2.0)
	return Vector2(
		cell.x * cell_size + cell_size / 2.0,
		cell.y * cell_size + cell_size / 2.0
	) - grid_offset

# Helper to check if a node has a property
func has_property(node: Object, property_name: String) -> bool:
	for property in node.get_property_list():
		if property.name == property_name:
			return true
	return false
