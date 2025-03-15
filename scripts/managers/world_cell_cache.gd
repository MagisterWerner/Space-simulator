# scripts/world/world_cell_cache.gd
extends Node
class_name WorldCellCache

signal cell_loaded(cell_coords)
signal cell_unloaded(cell_coords)
signal player_cell_changed(old_cell, new_cell)

# Cache configuration
@export_group("Cache Configuration")
@export var active_cell_radius: int = 2  # How many cells around player to keep active
@export var preload_cell_radius: int = 3  # How many cells to preload around player
@export var unload_distance: int = 4  # Distance in cells before unloading content
@export var cell_processing_per_frame: int = 1  # How many cells to process each frame

# Debug options
@export_group("Debug")
@export var debug_mode: bool = false
@export var log_cell_changes: bool = false
@export var visualize_active_cells: bool = false

# Internal state
var _loaded_cells = {}  # cell_coords -> CellContent
var _active_cells = []  # List of cell coordinates that are currently active
var _preloaded_cells = []  # List of cell coordinates that are currently preloaded
var _cells_to_load = []  # Queue of cells to be loaded
var _cells_to_unload = []  # Queue of cells to be unloaded
var _current_player_cell = Vector2i(-1, -1)
var _processing_enabled: bool = true

# Spawners and generators
var _world_generator = null
var _spawner_manager = null
var _content_registry = null

# Game settings reference
var _game_settings = null

# Cell content class
class CellContent:
	var cell: Vector2i
	var entities = []
	var terrain_type: String = ""
	var is_active: bool = false
	var is_player_cell: bool = false
	var neighbor_distance: int = -1  # Distance from player cell
	var generated: bool = false
	var generation_started: bool = false
	
	func _init(p_cell: Vector2i):
		cell = p_cell

func _ready() -> void:
	# Find game settings
	var main_scene = get_tree().current_scene
	_game_settings = main_scene.get_node_or_null("GameSettings")
	if _game_settings:
		debug_mode = _game_settings.debug_mode
	
	# Find world generator
	_world_generator = get_node_or_null("/root/WorldGenerator")
	if not _world_generator and get_tree().current_scene:
		_world_generator = get_tree().current_scene.get_node_or_null("WorldGenerator")
	
	# Find spawner manager
	_spawner_manager = get_node_or_null("/root/SpawnerManager")
	if not _spawner_manager and get_tree().current_scene:
		_spawner_manager = get_tree().current_scene.get_node_or_null("SpawnerManager")
	
	# Find content registry
	_content_registry = get_node_or_null("/root/ContentRegistry")
	if not _content_registry and get_tree().current_scene:
		_content_registry = get_tree().current_scene.get_node_or_null("ContentRegistry")
	
	# Connect to grid manager for player cell updates
	if has_node("/root/GridManager"):
		var grid_manager = get_node("/root/GridManager")
		if grid_manager.has_signal("player_cell_changed") and not grid_manager.is_connected("player_cell_changed", _on_player_cell_changed):
			grid_manager.connect("player_cell_changed", _on_player_cell_changed)
		
		# Get initial player cell
		_current_player_cell = grid_manager.get_player_cell()
	
	# Start processing cells
	set_process(true)

func _process(_delta: float) -> void:
	if not _processing_enabled:
		return
	
	# Process cell loading queue
	for i in range(min(cell_processing_per_frame, _cells_to_load.size())):
		if _cells_to_load.is_empty():
			break
		
		var cell = _cells_to_load.pop_front()
		_load_cell(cell)
	
	# Process cell unloading queue
	for i in range(min(cell_processing_per_frame, _cells_to_unload.size())):
		if _cells_to_unload.is_empty():
			break
		
		var cell = _cells_to_unload.pop_front()
		_unload_cell(cell)

func _on_player_cell_changed(old_cell: Vector2i, new_cell: Vector2i) -> void:
	if old_cell == new_cell:
		return
	
	if log_cell_changes and debug_mode:
		print("WorldCellCache: Player cell changed from ", old_cell, " to ", new_cell)
	
	# Update current player cell
	_current_player_cell = new_cell
	
	# Emit our own signal
	player_cell_changed.emit(old_cell, new_cell)
	
	# Make sure player cell is loaded first
	if not _loaded_cells.has(new_cell):
		_cells_to_load.push_front(new_cell)  # Priority load
	elif _loaded_cells[new_cell] and not _loaded_cells[new_cell].is_active:
		_activate_cell(new_cell)
	
	# Update which cells should be loaded/unloaded
	_update_cell_status()

# Update status of all cells based on player position
func _update_cell_status() -> void:
	# Skip if player cell is invalid
	if _current_player_cell == Vector2i(-1, -1):
		return
	
	# Calculate which cells should be active
	var cells_to_activate = _get_cells_in_radius(_current_player_cell, active_cell_radius)
	var cells_to_preload = _get_cells_in_radius(_current_player_cell, preload_cell_radius)
	
	# Mark cells as active/inactive
	for cell in cells_to_activate:
		if not _loaded_cells.has(cell):
			# Queue for loading if not loaded yet
			if not _cells_to_load.has(cell):
				_cells_to_load.append(cell)
		elif not _loaded_cells[cell].is_active:
			# Activate if loaded but not active
			_activate_cell(cell)
		
		# Make sure it's in the active cells list
		if not _active_cells.has(cell):
			_active_cells.append(cell)
	
	# Update neighbor distance for all loaded cells
	for cell in _loaded_cells:
		if _loaded_cells[cell]:
			_loaded_cells[cell].neighbor_distance = _calculate_cell_distance(cell, _current_player_cell)
			_loaded_cells[cell].is_player_cell = (cell == _current_player_cell)
	
	# Check which active cells should be deactivated
	var cells_to_deactivate = []
	for cell in _active_cells:
		if not cells_to_activate.has(cell):
			cells_to_deactivate.append(cell)
	
	# Deactivate cells that are now too far
	for cell in cells_to_deactivate:
		_deactivate_cell(cell)
		_active_cells.erase(cell)
	
	# Update preloaded cells list
	for cell in cells_to_preload:
		if not _loaded_cells.has(cell) and not _cells_to_load.has(cell):
			# Queue for loading if not loaded yet
			_cells_to_load.append(cell)
		
		# Make sure it's in the preloaded cells list
		if not _preloaded_cells.has(cell):
			_preloaded_cells.append(cell)
	
	# Check which cells should be unloaded
	for cell in _loaded_cells.keys():
		var distance = _calculate_cell_distance(cell, _current_player_cell)
		if distance > unload_distance:
			if not _cells_to_unload.has(cell):
				_cells_to_unload.append(cell)

# Calculate Manhattan distance between cells
func _calculate_cell_distance(cell1: Vector2i, cell2: Vector2i) -> int:
	return abs(cell1.x - cell2.x) + abs(cell1.y - cell2.y)

# Get cells within a radius (Manhattan distance) of a center cell
func _get_cells_in_radius(center: Vector2i, radius: int) -> Array:
	var cells = []
	
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if abs(dx) + abs(dy) <= radius:  # Manhattan distance check
				var cell = Vector2i(center.x + dx, center.y + dy)
				if _is_valid_cell(cell):
					cells.append(cell)
	
	return cells

# Check if a cell is valid (within grid)
func _is_valid_cell(cell: Vector2i) -> bool:
	if _game_settings and _game_settings.has_method("is_valid_cell"):
		return _game_settings.is_valid_cell(cell)
	
	# Simple fallback - assuming square grid
	var grid_size = 10
	if _game_settings:
		grid_size = _game_settings.grid_size
	
	return (
		cell.x >= 0 and cell.x < grid_size and
		cell.y >= 0 and cell.y < grid_size
	)

# Load a cell's content
func _load_cell(cell: Vector2i) -> void:
	# Skip invalid cells
	if not _is_valid_cell(cell):
		return
	
	# Create cell content if it doesn't exist
	if not _loaded_cells.has(cell):
		_loaded_cells[cell] = CellContent.new(cell)
	
	var cell_content = _loaded_cells[cell]
	
	# Skip if already fully generated
	if cell_content.generated:
		return
	
	# Skip if generation already started
	if cell_content.generation_started:
		return
	
	# Mark generation as started
	cell_content.generation_started = true
	
	# Check if content is available in registry
	var pre_generated_content = _get_content_from_registry(cell)
	if pre_generated_content and not pre_generated_content.is_empty():
		# Use pre-generated content
		_apply_pre_generated_content(cell, pre_generated_content)
	else:
		# Generate new content
		_generate_cell_content(cell)
	
	# Mark cell as active if it should be
	var is_in_active_radius = _calculate_cell_distance(cell, _current_player_cell) <= active_cell_radius
	if is_in_active_radius:
		_activate_cell(cell)
		if not _active_cells.has(cell):
			_active_cells.append(cell)
	
	# Mark cell as generated
	cell_content.generated = true
	
	# Emit signal
	cell_loaded.emit(cell)
	
	if debug_mode and log_cell_changes:
		print("WorldCellCache: Cell loaded at ", cell)

# Try to get content from registry
func _get_content_from_registry(cell: Vector2i) -> Dictionary:
	if _content_registry and _content_registry.has_method("get_world_cell_content"):
		return _content_registry.get_world_cell_content(cell)
	return {}

# Apply pre-generated content to a cell
func _apply_pre_generated_content(cell: Vector2i, content: Dictionary) -> void:
	if content.is_empty():
		return
	
	var cell_content = _loaded_cells[cell]
	
	# Apply terrain type if specified
	if content.has("terrain_type"):
		cell_content.terrain_type = content.terrain_type
	
	# Instantiate entities from pre-generated data
	if content.has("entities") and _spawner_manager:
		for entity_data in content.entities:
			var entity = _spawner_manager.spawn_entity(entity_data)
			if entity:
				cell_content.entities.append(entity)

# Generate content for a cell
func _generate_cell_content(cell: Vector2i) -> void:
	var cell_content = _loaded_cells[cell]
	
	# Use world generator if available
	if _world_generator and _world_generator.has_method("generate_entity"):
		# Try to generate planet
		var planet_cell = _world_generator.generate_entity("terran_planet", {"cell": cell})
		if planet_cell != Vector2i(-1, -1):
			# Get the entities at this cell
			var planet_entities = _world_generator.get_cell_entities(cell)
			cell_content.entities.append_array(planet_entities)
			cell_content.terrain_type = "planet"
		else:
			# Try asteroid field if no planet
			var asteroid_field_cell = _world_generator.generate_entity("asteroid_field", {"cell": cell})
			if asteroid_field_cell != Vector2i(-1, -1):
				var field_entities = _world_generator.get_cell_entities(cell)
				cell_content.entities.append_array(field_entities)
				cell_content.terrain_type = "asteroid_field"
			else:
				# Generate station occasionally
				var rng = RandomNumberGenerator.new()
				rng.seed = hash(str(cell)) + hash(str(_current_player_cell))
				if rng.randf() < 0.1:  # 10% chance
					var station_cell = _world_generator.generate_entity("station", {"cell": cell})
					if station_cell != Vector2i(-1, -1):
						var station_entities = _world_generator.get_cell_entities(cell)
						cell_content.entities.append_array(station_entities)
						cell_content.terrain_type = "station"
	elif _spawner_manager:
		# Fallback using spawner manager directly
		# Generate content based on deterministic random value
		var rng = RandomNumberGenerator.new()
		rng.seed = hash(str(cell))
		var roll = rng.randf()
		
		if roll < 0.05:  # 5% chance for planet
			var planet = _spawner_manager.spawn_planet_at_cell(cell)
			if planet:
				cell_content.entities.append(planet)
				cell_content.terrain_type = "planet"
		elif roll < 0.15:  # 10% chance for asteroid field
			var field = _spawner_manager.spawn_asteroid_field_at_cell(cell)
			if field:
				cell_content.entities.append(field)
				cell_content.terrain_type = "asteroid_field"
		elif roll < 0.2:  # 5% chance for station
			var station_type = rng.randi() % 4  # Random station type
			var station = _spawner_manager.spawn_station_at_cell(cell, station_type)
			if station:
				cell_content.entities.append(station)
				cell_content.terrain_type = "station"

# Activate a cell (make entities visible and active)
func _activate_cell(cell: Vector2i) -> void:
	if not _loaded_cells.has(cell):
		return
	
	var cell_content = _loaded_cells[cell]
	if cell_content.is_active:
		return
	
	# Activate all entities in the cell
	for entity in cell_content.entities:
		if not is_instance_valid(entity):
			continue
		
		entity.visible = true
		
		# Activate components if this is a component-based entity
		if entity.has_method("activate_components"):
			entity.activate_components()
		
		# Enable physics if this is a physics body
		if entity is PhysicsBody2D and "physics_material_override" in entity:
			entity.set_deferred("sleeping", false)
	
	# Mark as active
	cell_content.is_active = true
	
	if debug_mode and log_cell_changes:
		print("WorldCellCache: Cell activated at ", cell)

# Deactivate a cell (make entities not process while still loaded)
func _deactivate_cell(cell: Vector2i) -> void:
	if not _loaded_cells.has(cell):
		return
	
	var cell_content = _loaded_cells[cell]
	if not cell_content.is_active:
		return
	
	# Deactivate all entities in the cell
	for entity in cell_content.entities:
		if not is_instance_valid(entity):
			continue
		
		# Keep visible but disable processing to save CPU
		
		# Deactivate components if this is a component-based entity
		if entity.has_method("deactivate_components"):
			entity.deactivate_components()
		
		# Disable physics if this is a physics body
		if entity is PhysicsBody2D and "physics_material_override" in entity:
			entity.set_deferred("sleeping", true)
	
	# Mark as inactive
	cell_content.is_active = false
	
	if debug_mode and log_cell_changes:
		print("WorldCellCache: Cell deactivated at ", cell)

# Unload a cell completely
func _unload_cell(cell: Vector2i) -> void:
	if not _loaded_cells.has(cell):
		return
	
	# Skip if cell is currently active
	if _active_cells.has(cell):
		return
	
	# Deactivate first if needed
	if _loaded_cells[cell].is_active:
		_deactivate_cell(cell)
	
	var cell_content = _loaded_cells[cell]
	
	# Destroy all entities in the cell
	for entity in cell_content.entities:
		if is_instance_valid(entity):
			entity.queue_free()
	
	# Remove cell from tracked lists
	_loaded_cells.erase(cell)
	_preloaded_cells.erase(cell)
	
	# Remove from loading queue if present
	var load_index = _cells_to_load.find(cell)
	if load_index >= 0:
		_cells_to_load.remove_at(load_index)
	
	# Emit signal
	cell_unloaded.emit(cell)
	
	if debug_mode and log_cell_changes:
		print("WorldCellCache: Cell unloaded at ", cell)

# PUBLIC API

# Force a cell to load
func load_cell(cell: Vector2i) -> void:
	if not _loaded_cells.has(cell) and not _cells_to_load.has(cell):
		_cells_to_load.append(cell)

# Force a cell to unload
func unload_cell(cell: Vector2i) -> void:
	if _loaded_cells.has(cell) and not _cells_to_unload.has(cell):
		_cells_to_unload.append(cell)

# Activate a specific cell
func activate_cell(cell: Vector2i) -> void:
	if _loaded_cells.has(cell) and not _loaded_cells[cell].is_active:
		_activate_cell(cell)
		if not _active_cells.has(cell):
			_active_cells.append(cell)

# Deactivate a specific cell
func deactivate_cell(cell: Vector2i) -> void:
	if _loaded_cells.has(cell) and _loaded_cells[cell].is_active:
		_deactivate_cell(cell)
		_active_cells.erase(cell)

# Check if a cell is loaded
func is_cell_loaded(cell: Vector2i) -> bool:
	return _loaded_cells.has(cell)

# Check if a cell is active
func is_cell_active(cell: Vector2i) -> bool:
	return _loaded_cells.has(cell) and _loaded_cells[cell].is_active

# Get all entities in a cell
func get_cell_entities(cell: Vector2i) -> Array:
	if _loaded_cells.has(cell):
		return _loaded_cells[cell].entities
	return []

# Get current player cell
func get_current_player_cell() -> Vector2i:
	return _current_player_cell

# Pause/resume cell processing
func set_processing_enabled(enabled: bool) -> void:
	_processing_enabled = enabled

# Clear all loaded cells
func clear_all_cells() -> void:
	# Clear queues
	_cells_to_load.clear()
	_cells_to_unload.clear()
	
	# Make copy of keys to avoid modifying during iteration
	var cells_to_unload = _loaded_cells.keys()
	for cell in cells_to_unload:
		_unload_cell(cell)
	
	_active_cells.clear()
	_preloaded_cells.clear()
