extends Node
class_name WorldSimulation

signal world_loaded
signal cell_loaded(cell_coords)
signal cell_unloaded(cell_coords)
signal entity_spawned(entity, entity_data)
signal entity_despawned(entity, entity_data)
signal player_cell_changed(old_cell, new_cell)

# Configuration
@export var active_cell_radius: int = 2  # Cells around player to keep loaded
@export var preload_cell_radius: int = 3  # Cells to preload data for
@export var unload_distance: int = 4     # When to unload distant cells
@export var max_cells_per_frame: int = 2 # Maximum cells to process per frame
@export var use_content_registry: bool = true # Use content registry for pre-generated content

# World state
var world_data: WorldData = null
var is_world_loaded: bool = false

# Cell tracking
var loaded_cells = {}  # Vector2i -> { entities: [], active: bool, entity_data: [], initialized: bool }
var active_cells = []
var preloaded_cells = []
var current_player_cell = Vector2i(-1, -1)

# Processing queues
var _cells_to_load = []
var _cells_to_unload = []

# Manager references
var _entity_manager = null
var _spawner_manager = null
var _game_settings = null
var _grid_manager = null
var _game_manager = null
var _content_registry = null

# Debug
var _debug_mode = false
var _processing_enabled = true

func _ready() -> void:
	# Add to group for easy access
	add_to_group("world_simulation")
	
	# Find manager references
	_entity_manager = get_node_or_null("/root/EntityManager")
	_game_settings = get_tree().current_scene.get_node_or_null("GameSettings")
	_grid_manager = get_node_or_null("/root/GridManager")
	_game_manager = get_node_or_null("/root/GameManager")
	_content_registry = get_node_or_null("/root/ContentRegistry")
	
	# Find spawner manager - try to get from scene first
	_spawner_manager = get_node_or_null("/root/SpawnerManager")
	if not _spawner_manager:
		var spawners = get_tree().get_nodes_in_group("spawner_managers")
		if not spawners.is_empty():
			_spawner_manager = spawners[0]
	
	# Debug mode
	if _game_settings:
		_debug_mode = _game_settings.debug_mode
	
	# Connect to grid manager signals
	if _grid_manager and _grid_manager.has_signal("player_cell_changed"):
		if not _grid_manager.is_connected("player_cell_changed", _on_player_cell_changed):
			_grid_manager.connect("player_cell_changed", _on_player_cell_changed)
	
	# Start processing
	set_process(true)

func _process(_delta: float) -> void:
	if not _processing_enabled:
		return
	
	# Process cell loading queue
	for i in range(min(max_cells_per_frame, _cells_to_load.size())):
		if _cells_to_load.is_empty():
			break
		
		var cell = _cells_to_load.pop_front()
		_load_cell(cell)
	
	# Process cell unloading queue
	for i in range(min(max_cells_per_frame, _cells_to_unload.size())):
		if _cells_to_unload.is_empty():
			break
		
		var cell = _cells_to_unload.pop_front()
		_unload_cell(cell)

# Load a world from WorldData
func load_world(data: WorldData) -> bool:
	if not _entity_manager or not _spawner_manager:
		push_error("WorldSimulation: Cannot load world - missing managers")
		return false
	
	world_data = data
	
	if _debug_mode:
		print("WorldSimulation: Loading world with seed " + str(world_data.seed_value))
	
	# Initialize tracking
	loaded_cells.clear()
	active_cells.clear()
	preloaded_cells.clear()
	_cells_to_load.clear()
	_cells_to_unload.clear()
	
	# Set current player position
	current_player_cell = world_data.player_start_cell
	if current_player_cell == Vector2i(-1, -1):
		# Default to center of grid
		var center = world_data.grid_size / 2
		current_player_cell = Vector2i(center, center)
	
	# Queue cells for preloading and activation
	_update_cell_status()
	
	is_world_loaded = true
	world_loaded.emit()
	
	return true

# Handle player cell change
func _on_player_cell_changed(old_cell: Vector2i, new_cell: Vector2i) -> void:
	if old_cell == new_cell:
		return
		
	current_player_cell = new_cell
	
	if _debug_mode:
		print("WorldSimulation: Player cell changed from ", old_cell, " to ", new_cell)
	
	# Make sure player cell is loaded first
	if not loaded_cells.has(new_cell):
		_cells_to_load.push_front(new_cell)  # Priority load
	elif loaded_cells[new_cell] and not loaded_cells[new_cell].active:
		_activate_cell(new_cell)
	
	# Update cell loading
	_update_cell_status()
	
	# Emit our own signal
	player_cell_changed.emit(old_cell, new_cell)

# Update which cells to load/unload based on player position
func _update_cell_status() -> void:
	# Skip if player cell is invalid
	if current_player_cell == Vector2i(-1, -1):
		return
	
	# Calculate which cells should be active
	var cells_to_activate = _get_cells_in_radius(current_player_cell, active_cell_radius)
	var cells_to_preload = _get_cells_in_radius(current_player_cell, preload_cell_radius)
	
	# Queue cells for loading/activation
	for cell in cells_to_activate:
		if not loaded_cells.has(cell):
			# Queue for loading if not loaded yet
			if not _cells_to_load.has(cell):
				_cells_to_load.append(cell)
		elif not loaded_cells[cell].active:
			# Activate if loaded but not active
			_activate_cell(cell)
		
		# Make sure it's in the active cells list
		if not active_cells.has(cell):
			active_cells.append(cell)
	
	# Update neighbor distance for all loaded cells
	for cell in loaded_cells:
		if loaded_cells[cell]:
			loaded_cells[cell].neighbor_distance = _calculate_cell_distance(cell, current_player_cell)
			loaded_cells[cell].is_player_cell = (cell == current_player_cell)
	
	# Check which active cells should be deactivated
	var cells_to_deactivate = []
	for cell in active_cells:
		if not cells_to_activate.has(cell):
			cells_to_deactivate.append(cell)
	
	# Deactivate cells that are now too far
	for cell in cells_to_deactivate:
		_deactivate_cell(cell)
		active_cells.erase(cell)
	
	# Preload cells
	for cell in cells_to_preload:
		if not loaded_cells.has(cell) and not _cells_to_load.has(cell) and not cells_to_activate.has(cell):
			# Queue for loading if not loaded yet and not already in queue
			_cells_to_load.append(cell)
		
		# Make sure it's in the preloaded cells list
		if not preloaded_cells.has(cell):
			preloaded_cells.append(cell)
	
	# Check which cells should be unloaded
	for cell in loaded_cells.keys():
		var distance = _calculate_cell_distance(cell, current_player_cell)
		if distance > unload_distance:
			if not _cells_to_unload.has(cell):
				_cells_to_unload.append(cell)

# Preload cell data (don't spawn entities yet)
func _preload_cell(cell: Vector2i) -> void:
	if not _is_valid_cell(cell) or loaded_cells.has(cell):
		return
	
	# Create tracking data
	loaded_cells[cell] = {
		"entities": [],  # Will be populated when activated
		"active": false,
		"entity_data": [],  # Store data for entities in this cell
		"initialized": false,
		"neighbor_distance": _calculate_cell_distance(cell, current_player_cell),
		"is_player_cell": (cell == current_player_cell),
		"terrain_type": ""
	}
	
	# Check content registry for pre-generated content if enabled
	if use_content_registry and _content_registry and _content_registry.has_method("get_world_cell_content"):
		var cell_content = _content_registry.get_world_cell_content(cell)
		if not cell_content.is_empty():
			_apply_pre_generated_content(cell, cell_content)
			loaded_cells[cell].initialized = true
			return
	
	# Gather entity data from world_data
	var cell_entities = []
	
	# Check for planets
	var planets = world_data.get_planets_in_cell(cell)
	cell_entities.append_array(planets)
	
	# Check for asteroid fields
	var asteroid_fields = world_data.get_asteroid_fields_in_cell(cell)
	cell_entities.append_array(asteroid_fields)
	
	# Store entity data
	loaded_cells[cell].entity_data = cell_entities
	loaded_cells[cell].initialized = true
	
	if _debug_mode:
		print("WorldSimulation: Preloaded cell " + str(cell) + " with " + str(cell_entities.size()) + " entities")

# Apply pre-generated content to a cell
func _apply_pre_generated_content(cell: Vector2i, content: Dictionary) -> void:
	if content.is_empty():
		return
	
	var cell_content = loaded_cells[cell]
	
	# Apply terrain type if specified
	if content.has("terrain_type"):
		cell_content.terrain_type = content.terrain_type
	
	# Store entity data
	if content.has("planets"):
		cell_content.entity_data.append_array(content.planets)
	
	if content.has("asteroid_fields"):
		cell_content.entity_data.append_array(content.asteroid_fields)
	
	# Also store generic entities if present
	if content.has("entities"):
		cell_content.entity_data.append_array(content.entities)

# Load and activate a cell
func _load_cell(cell: Vector2i) -> void:
	if not _is_valid_cell(cell):
		return
	
	# If not preloaded, preload first
	if not loaded_cells.has(cell):
		_preload_cell(cell)
	
	# Activate if in active radius
	var distance = _calculate_cell_distance(cell, current_player_cell)
	if distance <= active_cell_radius:
		_activate_cell(cell)
	
	# Signal that cell is loaded
	cell_loaded.emit(cell)

# Activate a cell (spawn entities)
func _activate_cell(cell: Vector2i) -> void:
	if not loaded_cells.has(cell) or loaded_cells[cell].active:
		return
	
	if _debug_mode:
		print("WorldSimulation: Activating cell " + str(cell))
	
	# Spawn all entities in this cell
	var entity_data_list = loaded_cells[cell].entity_data
	var spawned_entities = []
	
	for entity_data in entity_data_list:
		# Spawn entity via spawner manager
		var entity = _spawner_manager.spawn_entity(entity_data)
		
		if entity:
			spawned_entities.append({
				"entity": entity,
				"data": entity_data
			})
			
			# Signal entity spawned
			entity_spawned.emit(entity, entity_data)
	
	# Track spawned entities
	loaded_cells[cell].entities = spawned_entities
	loaded_cells[cell].active = true

# Deactivate a cell (despawn entities but keep data)
func _deactivate_cell(cell: Vector2i) -> void:
	if not loaded_cells.has(cell) or not loaded_cells[cell].active:
		return
	
	if _debug_mode:
		print("WorldSimulation: Deactivating cell " + str(cell))
	
	# Despawn all entities
	for entity_info in loaded_cells[cell].entities:
		if is_instance_valid(entity_info.entity):
			# Signal entity despawned
			entity_despawned.emit(entity_info.entity, entity_info.data)
			
			# Free the entity
			entity_info.entity.queue_free()
	
	# Clear entity list but keep data
	loaded_cells[cell].entities.clear()
	loaded_cells[cell].active = false

# Unload a cell completely
func _unload_cell(cell: Vector2i) -> void:
	if not loaded_cells.has(cell):
		return
	
	if _debug_mode:
		print("WorldSimulation: Unloading cell " + str(cell))
	
	# If active, deactivate first
	if loaded_cells[cell].active:
		_deactivate_cell(cell)
	
	# Remove cell
	loaded_cells.erase(cell)
	preloaded_cells.erase(cell)
	
	# Signal that cell is unloaded
	cell_unloaded.emit(cell)

# Get cells within a radius of a center cell
func _get_cells_in_radius(center: Vector2i, radius: int) -> Array:
	var cells = []
	
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if abs(dx) + abs(dy) <= radius:  # Manhattan distance check
				var cell = Vector2i(center.x + dx, center.y + dy)
				if _is_valid_cell(cell):
					cells.append(cell)
	
	return cells

# Calculate Manhattan distance between cells
func _calculate_cell_distance(cell1: Vector2i, cell2: Vector2i) -> int:
	return abs(cell1.x - cell2.x) + abs(cell1.y - cell2.y)

# Check if a cell is valid
func _is_valid_cell(cell: Vector2i) -> bool:
	if world_data:
		return cell.x >= 0 and cell.x < world_data.grid_size and cell.y >= 0 and cell.y < world_data.grid_size
	
	if _game_settings and _game_settings.has_method("is_valid_cell"):
		return _game_settings.is_valid_cell(cell)
	
	if _grid_manager and _grid_manager.has_method("is_valid_cell"):
		return _grid_manager.is_valid_cell(cell)
	
	# Default check
	return cell.x >= 0 and cell.x < 10 and cell.y >= 0 and cell.y < 10

# Get world position for a cell (for spawning entities)
func _get_cell_world_position(cell: Vector2i) -> Vector2:
	if _grid_manager and _grid_manager.has_method("cell_to_world"):
		return _grid_manager.cell_to_world(cell)
		
	if _game_settings and _game_settings.has_method("get_cell_world_position"):
		return _game_settings.get_cell_world_position(cell)
	
	# Fallback implementation
	var cell_size = 1024
	var grid_size = 10
	
	if _game_settings:
		cell_size = _game_settings.grid_cell_size
		grid_size = _game_settings.grid_size
		
	var grid_offset = Vector2(-cell_size * grid_size / 2.0, -cell_size * grid_size / 2.0)
	return grid_offset + Vector2(
		cell.x * cell_size + cell_size / 2.0,
		cell.y * cell_size + cell_size / 2.0
	)

# Convert world position to cell coordinates
func _world_to_cell(position: Vector2) -> Vector2i:
	if _grid_manager and _grid_manager.has_method("world_to_cell"):
		return _grid_manager.world_to_cell(position)
		
	if _game_settings and _game_settings.has_method("get_cell_coords"):
		return _game_settings.get_cell_coords(position)
	
	# Fallback implementation
	var cell_size = 1024
	var grid_size = 10
	
	if _game_settings:
		cell_size = _game_settings.grid_cell_size
		grid_size = _game_settings.grid_size
		
	var grid_offset = Vector2(-cell_size * grid_size / 2.0, -cell_size * grid_size / 2.0)
	var local_pos = position - grid_offset
	
	return Vector2i(
		int(floor(local_pos.x / cell_size)),
		int(floor(local_pos.y / cell_size))
	)

# Update world data from active entities
func _update_world_data_from_entities() -> void:
	if not world_data:
		return
		
	# For each active cell, update entity data in world_data
	for cell in active_cells:
		if loaded_cells.has(cell) and loaded_cells[cell].active:
			for entity_info in loaded_cells[cell].entities:
				if is_instance_valid(entity_info.entity):
					var entity = entity_info.entity
					var data = entity_info.data
					
					# Update position
					if "global_position" in entity:
						data.position = entity.global_position
					
					# Update type-specific data
					if data is PlanetData and "rotation" in entity:
						# Update planet rotation or other state
						data.properties["rotation"] = entity.rotation
					elif data is AsteroidData and entity is RigidBody2D:
						# Update asteroid physics state
						data.linear_velocity = entity.linear_velocity
						data.angular_velocity = entity.angular_velocity
						if "rotation" in entity:
							data.properties["rotation"] = entity.rotation
	
	# Update player start position
	if _entity_manager and _entity_manager.has_method("get_player_ship"):
		var player_ship = _entity_manager.get_player_ship()
		if player_ship and is_instance_valid(player_ship):
			world_data.player_start_position = player_ship.global_position
			world_data.player_start_cell = current_player_cell

# PUBLIC API

# Force load a specific cell
func load_cell(cell: Vector2i) -> void:
	if _is_valid_cell(cell) and not loaded_cells.has(cell) and not _cells_to_load.has(cell):
		_cells_to_load.append(cell)

# Force activate a specific cell
func activate_cell(cell: Vector2i) -> void:
	if _is_valid_cell(cell) and loaded_cells.has(cell) and not loaded_cells[cell].active:
		_activate_cell(cell)

# Force deactivate a specific cell
func deactivate_cell(cell: Vector2i) -> void:
	if loaded_cells.has(cell) and loaded_cells[cell].active:
		_deactivate_cell(cell)

# Force unload a specific cell
func unload_cell(cell: Vector2i) -> void:
	if loaded_cells.has(cell):
		if not _cells_to_unload.has(cell):
			_cells_to_unload.append(cell)

# Get entities in a specific cell
func get_entities_in_cell(cell: Vector2i) -> Array:
	if loaded_cells.has(cell) and loaded_cells[cell].active:
		var result = []
		for entity_info in loaded_cells[cell].entities:
			if is_instance_valid(entity_info.entity):
				result.append(entity_info.entity)
		return result
	
	return []

# Check if a cell is loaded
func is_cell_loaded(cell: Vector2i) -> bool:
	return loaded_cells.has(cell)

# Check if a cell is active
func is_cell_active(cell: Vector2i) -> bool:
	return loaded_cells.has(cell) and loaded_cells[cell].active

# Generate new world data (or use existing) and load it
func generate_and_load_world(seed_value: int = 0) -> bool:
	if _debug_mode:
		print("WorldSimulation: Generating new world with seed " + str(seed_value))
	
	# Create world generator
	var world_generator = WorldGenerator.new()
	add_child(world_generator)
	
	# Generate world data
	var data = world_generator.generate_world_data(seed_value)
	
	# Remove generator
	world_generator.queue_free()
	
	# Load the generated world
	return load_world(data)

# Save the current world state
func save_world_state(file_path: String = "user://world_state.save") -> Error:
	if not world_data:
		return ERR_UNAVAILABLE
	
	# Update world data from active entities
	_update_world_data_from_entities()
	
	# Save to file
	return world_data.save_to_file(file_path)

# Pause/resume cell processing
func set_processing_enabled(enabled: bool) -> void:
	_processing_enabled = enabled

# Update current player cell based on player position
func update_player_cell() -> void:
	# Find player
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	
	var player = players[0]
	if not is_instance_valid(player):
		return
	
	var player_position = player.global_position
	var new_cell = _world_to_cell(player_position)
	
	if new_cell != current_player_cell:
		var old_cell = current_player_cell
		_on_player_cell_changed(old_cell, new_cell)

# Clear all cells (useful for scene transitions)
func clear_all_cells() -> void:
	# Clear queues
	_cells_to_load.clear()
	_cells_to_unload.clear()
	
	# Make copy of keys to avoid modifying during iteration
	var cells_to_unload = loaded_cells.keys()
	for cell in cells_to_unload:
		_unload_cell(cell)
	
	active_cells.clear()
	preloaded_cells.clear()
