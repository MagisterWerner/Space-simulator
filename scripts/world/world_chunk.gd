# scripts/world/world_chunk.gd
extends Node2D
class_name WorldChunk

# Chunk coordinates and data
var coordinates: Vector2i
var chunk_data: Dictionary
var is_full_detail: bool = true

# Entity management
var _entities: Array = []
var _entity_container: Node

# Visibility optimization
var _is_active: bool = true
var _visibility_range: float = 1500
var _last_camera_position: Vector2 = Vector2.ZERO

func _ready():
	# Create container for entities
	_entity_container = Node2D.new()
	_entity_container.name = "Entities"
	add_child(_entity_container)
	
	# Set chunk name for debugging
	name = "Chunk_%d_%d" % [coordinates.x, coordinates.y]
	
	# We'll check camera position in _process instead of using a signal
	# This avoids the nonexistent signal error

# Initialize the chunk with data
func initialize(coords: Vector2i, data: Dictionary, full_detail: bool):
	coordinates = coords
	chunk_data = data
	is_full_detail = full_detail
	
	# Position the chunk in the world
	global_position = Vector2(coords.x * 1000, coords.y * 1000)
	
	# If this is a preloaded chunk, don't do full initialization
	if not full_detail:
		# Just create minimal background elements
		_create_background()
		return
	
	# Generate background elements
	_create_background()
	
	# Create entities from data (actual entities added separately via add_entity())
	for i in range(chunk_data.entities.size()):
		# Note: actual entity instantiation is handled by WorldChunkManager
		# This just prepares any additional data needed
		pass

# Add an entity to this chunk
func add_entity(entity: Node) -> void:
	_entity_container.add_child(entity)
	_entities.append(entity)
	
	# Set metadata to identify entity type for pooling
	if not entity.has_meta("entity_type"):
		for type in ["asteroid", "enemy_ship", "station"]:
			if type in entity.get_path():
				entity.set_meta("entity_type", type)
				break

# Get all entities in this chunk
func get_entities() -> Array:
	return _entities

# Prioritize entity processing based on distance
func _process(delta):
	if not is_full_detail or not _is_active:
		return
	
	# Check camera position to update visibility
	var camera = get_viewport().get_camera_2d()
	if camera and is_instance_valid(camera):
		var camera_position = camera.global_position
		
		# Only update if camera moved significantly
		if camera_position.distance_to(_last_camera_position) > 50:
			_last_camera_position = camera_position
			_update_visibility(camera_position)
	
	var player = get_tree().get_nodes_in_group("player")[0] if get_tree().get_nodes_in_group("player").size() > 0 else null
	if not player:
		return
	
	# Update entities based on distance from player
	for entity in _entities:
		var distance = entity.global_position.distance_to(player.global_position)
		
		# Skip processing for very distant entities
		if distance > 2000:
			if entity.has_method("set_processing"):
				entity.set_processing(false)
			continue
			
		# Full processing for close entities
		if distance < 1000:
			if entity.has_method("set_processing"):
				entity.set_processing(true)
			# Update physics at full rate
			if entity is RigidBody2D:
				entity.set_physics_process(true)
				
		# Reduced processing for medium distance
		elif distance < 1500:
			if entity.has_method("set_processing"):
				entity.set_processing(true)
			# Update physics at reduced rate
			if entity is RigidBody2D:
				entity.set_physics_process(Engine.get_physics_frames() % 2 == 0)
				
		# Minimal processing for distant entities
		else:
			if entity.has_method("set_processing"):
				entity.set_processing(Engine.get_physics_frames() % 3 == 0)
			# Very minimal physics updates
			if entity is RigidBody2D:
				entity.set_physics_process(Engine.get_physics_frames() % 4 == 0)

# Update visibility based on camera position
func _update_visibility(camera_position: Vector2):
	var chunk_center = global_position + Vector2(500, 500)
	var distance = chunk_center.distance_to(camera_position)
	
	# Activate/deactivate based on visibility
	var should_be_active = distance < _visibility_range
	if should_be_active != _is_active:
		_is_active = should_be_active
		_entity_container.visible = _is_active
		
		# Disable processing when not active
		for entity in _entities:
			if entity.has_method("set_processing"):
				entity.set_processing(_is_active)
			if entity is RigidBody2D:
				entity.set_physics_process(_is_active)

# Create background elements
func _create_background():
	var background = Node2D.new()
	background.name = "Background"
	add_child(background)
	
	# Use chunk_data.background to determine appearance
	var bg_type = chunk_data.background.type
	var density = chunk_data.background.density
	
	# Create deterministic background decorations
	var base_id = _get_chunk_id(coordinates)
	
	# Number of background elements depends on density
	var element_count = int(20 * density)
	
	for i in range(element_count):
		var element_id = base_id + i * 10
		
		# Position within chunk
		var pos_x = SeedManager.get_random_value(element_id + 1, 0, 1000)
		var pos_y = SeedManager.get_random_value(element_id + 2, 0, 1000)
		
		# Simple background element (e.g., star)
		var element = ColorRect.new()
		element.color = Color(1, 1, 1, 0.5)
		element.size = Vector2(2, 2)
		element.position = Vector2(pos_x, pos_y)
		background.add_child(element)

# Get a consistent chunk ID for deterministic generation
func _get_chunk_id(coords: Vector2i) -> int:
	# Create a base chunk ID using the coordinate
	# We use prime multipliers to avoid grid patterns
	return 12347 + (coords.x * 7919) + (coords.y * 6837)

# Set chunk detail level
func set_detail_level(full_detail: bool):
	is_full_detail = full_detail
	# Implementation depends on how you want to visualize detail levels
