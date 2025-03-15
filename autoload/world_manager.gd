# scripts/autoload/world_manager.gd
# Centralized management of world structure and content loading
extends Node

# ----- SIGNALS -----
signal world_ready
signal world_generation_started
signal world_generation_progress(progress)
signal world_generation_completed
signal cell_loaded(cell_coords)
signal cell_activated(cell_coords)
signal cell_deactivated(cell_coords)
signal cell_unloaded(cell_coords)
signal player_cell_changed(old_cell, new_cell)

# ----- CONFIGURATION -----
@export var active_cell_radius: int = 2  # Cells around player to keep loaded
@export var preload_cell_radius: int = 3  # Cells to preload data for
@export var unload_distance: int = 4     # When to unload distant cells
@export var background_generation: bool = true
@export var max_cells_per_frame: int = 2 # Maximum cells to process per frame

# ----- WORLD STATE -----
var world_data: WorldData = null
var is_world_loaded: bool = false
var is_world_ready: bool = false
var current_seed: int = 0

# ----- CELL TRACKING -----
var loaded_cells: Dictionary = {}  # Vector2i -> { entities: [], active: bool, initialized: bool }
var active_cells: Array[Vector2i] = []
var preloaded_cells: Array[Vector2i] = []
var current_player_cell = Vector2i(-1, -1)

# ----- PROCESSING QUEUES -----
var _cells_to_load: Array[Vector2i] = []
var _cells_to_unload: Array[Vector2i] = []
var _cells_to_activate: Array[Vector2i] = []
var _cells_to_deactivate: Array[Vector2i] = []

# ----- DEPENDENCIES -----
var _content_registry: ContentRegistry = null
var _entity_manager = null
var _spawner_manager = null
var _game_settings = null

# ----- OPTIMIZATION -----
var _player_last_position: Vector2 = Vector2.ZERO
var _player_position_check_timer: float = 0.0
var _cells_processed_this_frame: int = 0
const PLAYER_POSITION_CHECK_INTERVAL: float = 0.2

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Find dependencies
	_content_registry = get_node_or_null("/root/ContentRegistry")
	_entity_manager = get_node_or_null("/root/EntityManager")
	_spawner_manager = get_node_or_null("/root/SpawnerManager")
	
	var main_scene = get_tree().current_scene
	_game_settings = main_scene.get_node_or_null("GameSettings")
	
	# Connect to SeedManager
	if has_node("/root/SeedManager"):
		if not SeedManager.is_connected("seed_changed", _on_seed_changed):
			SeedManager.connect("seed_changed", _on_seed_changed)

# Setup world with a specific seed
func setup_world(seed_value: int) -> void:
	current_seed = seed_value
	
	# Update SeedManager
	if has_node("/root/SeedManager"):
		SeedManager.set_seed(seed_value)
	
	# Create content registry if needed
	if not _content_registry:
		_content_registry = ContentRegistry.new()
		_content_registry.name = "ContentRegistry"
		get_tree().root.add_child(_content_registry)
	
	# Initialize content registry with seed
	_content_registry.initialize(seed_value, _game_settings and _game_settings.debug_mode)
	
	# Initialize world data
	world_data = _content_registry.world_data
	world_data.grid_size = _game_settings.grid_size if _game_settings else 10
	world_data.grid_cell_size = _game_settings.grid_cell_size if _game_settings else 1024
	
	is_world_loaded = true

# Generate the world
func generate_world() -> void:
	if not is_world_loaded or not world_data:
		push_error("WorldManager: World not loaded, cannot generate")
		return
	
	# Signal start of generation
	world_generation_started.emit()
	
	# Ensure world has a seed
	if current_seed == 0 and _game_settings:
		current_seed = _game_settings.get_seed()
	
	# Determine which cells to generate
	var cells_to_generate = []
	var priority_cells = []
	
	# Add player starting area to priority list
	if world_data.player_start_cell != Vector2i(-1, -1):
		priority_cells.append(world_data.player_start_cell)
		
		# Add cells around player start as priorities
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				var cell = world_data.player_start_cell + Vector2i(dx, dy)
				if is_valid_cell(cell) and cell != world_data.player_start_cell:
					priority_cells.append(cell)
	else:
		# Default to center of grid if no player start cell
		var center_cell = Vector2i(world_data.grid_size / 2, world_data.grid_size / 2)
		priority_cells.append(center_cell)
		
		# Add cells around center as priorities
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				var cell = center_cell + Vector2i(dx, dy)
				if is_valid_cell(cell) and cell != center_cell:
					priority_cells.append(cell)
	
	# Add all cells to generation list
	for x in range(world_data.grid_size):
		for y in range(world_data.grid_size):
			var cell = Vector2i(x, y)
			if not priority_cells.has(cell):
				cells_to_generate.append(cell)
	
	# Start background generation
	if background_generation and _content_registry:
		_content_registry.start_background_generation(cells_to_generate, priority_cells)
		
		# Connect to content registry for progress updates
		if not _content_registry.is_connected("content_cache_updated", _on_content_cache_updated):
			_content_registry.connect("content_cache_updated", _on_content_cache_updated)
	else:
		# Fallback to immediate generation of priority cells
		for cell in priority_cells:
			_generate_cell_content(cell)
			
		# Signal completion
		world_generation_completed.emit()
	
	# Mark world as ready
	is_world_ready = true
	world_ready.emit()

# Main update loop
func _process(delta):
	if not is_world_loaded or not is_world_ready:
		return
	
	# Update player position check timer
	_player_position_check_timer += delta
	if _player_position_check_timer >= PLAYER_POSITION_CHECK_INTERVAL:
		_player_position_check_timer = 0.0
		_update_player_cell()
	
	# Reset cells processed counter
	_cells_processed_this_frame = 0
	
	# Process cell queues
	_process_cell_queues()

# Process cell management queues
func _process_cell_queues() -> void:
	# First handle cells to activate (highest priority)
	while not _cells_to_activate.is_empty() and _cells_processed_this_frame < max_cells_per_frame:
		var cell = _cells_to_activate.pop_front()
		_activate_cell(cell)
		_cells_processed_this_frame += 1
	
	# Then handle cells to load
	while not _cells_to_load.is_empty() and _cells_processed_this_frame < max_cells_per_frame:
		var cell = _cells_to_load.pop_front()
		_load_cell(cell)
		_cells_processed_this_frame += 1
	
	# Then handle cells to deactivate
	while not _cells_to_deactivate.is_empty() and _cells_processed_this_frame < max_cells_per_frame:
		var cell = _cells_to_deactivate.pop_front()
		_deactivate_cell(cell)
		_cells_processed_this_frame += 1
	
	# Finally handle cells to unload
	while not _cells_to_unload.is_empty() and _cells_processed_this_frame < max_cells_per_frame:
		var cell = _cells_to_unload.pop_front()
		_unload_cell(cell)
		_cells_processed_this_frame += 1

# Update player cell and manage loading/unloading
func _update_player_cell() -> void:
	var player = _get_player()
	if not player or not "global_position" in player:
		return
	
	var player_position = player.global_position
	
	# Skip if player hasn't moved much
	if player_position.distance_to(_player_last_position) < world_data.grid_cell_size / 8.0:
		return
	
	_player_last_position = player_position
	
	# Calculate cell coordinates
	var cell_coords = world_to_cell(player_position)
	
	# Check if cell changed
	if cell_coords != current_player_cell:
		var old_cell = current_player_cell
		current_player_cell = cell_coords
		
		# Emit signal
		player_cell_changed.emit(old_cell, current_player_cell)
		
		# Update cell loading
		_update_cell_status()

# Update which cells to load/unload based on player position
func _update_cell_status() -> void:
	# Skip if player cell is invalid
	if current_player_cell == Vector2i(-1, -1):
		return
	
	# Calculate which cells should be active
	var cells_to_activate = _get_cells_in_radius(current_player_cell, active_cell_radius)
	var cells_to_preload = _get_cells_in_radius(current_player_cell, preload_cell_radius)
	
	# Handle cells that should be active
	for cell in cells_to_activate:
		if not loaded_cells.has(cell):
			# Queue for loading if not loaded yet
			if not _cells_to_load.has(cell):
				_cells_to_load.append(cell)
		elif not loaded_cells[cell].active:
			# Queue for activation if loaded but not active
			if not _cells_to_activate.has(cell):
				_cells_to_activate.append(cell)
		
		# Make sure it's in the active cells list
		if not active_cells.has(cell):
			active_cells.append(cell)
	
	# Check which active cells should be deactivated
	for cell in active_cells.duplicate():
		if not cells_to_activate.has(cell):
			if not _cells_to_deactivate.has(cell):
				_cells_to_deactivate.append(cell)
	
	# Handle cells that should be preloaded
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

# Cell management methods

# Load a cell
func _load_cell(cell: Vector2i) -> void:
	if not is_valid_cell(cell):
		return
	
	# If already loaded, skip
	if loaded_cells.has(cell):
		return
	
	# Create tracking data
	loaded_cells[cell] = {
		"entities": [],  # Will be populated when activated
		"active": false,
		"initialized": false,
		"neighbor_distance": _calculate_cell_distance(cell, current_player_cell),
	}
	
	# Preload entities if content registry has them
	if _content_registry:
		# Generate content if needed
		if not world_data.is_cell_generated(cell):
			_generate_cell_content(cell)
	
	# Mark as initialized
	loaded_cells[cell].initialized = true
	
	# Signal that cell is loaded
	cell_loaded.emit(cell)

# Activate a cell (spawn entities)
func _activate_cell(cell: Vector2i) -> void:
	if not is_valid_cell(cell) or not loaded_cells.has(cell) or loaded_cells[cell].active:
		return
	
	# Get content for this cell
	var cell_entities = []
	if _content_registry:
		cell_entities = _content_registry.get_cell_content(cell)
	
	# Spawn entities through proper spawner
	for entity_data in cell_entities:
		var entity = _spawn_entity(entity_data)
		if entity:
			loaded_cells[cell].entities.append({
				"entity": entity,
				"data": entity_data
			})
	
	# Mark as active
	loaded_cells[cell].active = true
	
	# Add to active cells list if not there
	if not active_cells.has(cell):
		active_cells.append(cell)
	
	# Signal activation
	cell_activated.emit(cell)

# Deactivate a cell (despawn entities but keep data)
func _deactivate_cell(cell: Vector2i) -> void:
	if not loaded_cells.has(cell) or not loaded_cells[cell].active:
		return
	
	# Despawn all entities
	for entity_info in loaded_cells[cell].entities:
		if is_instance_valid(entity_info.entity):
			if _entity_manager:
				_entity_manager.deregister_entity(entity_info.entity)
			entity_info.entity.queue_free()
	
	# Clear entity list but keep data
	loaded_cells[cell].entities.clear()
	loaded_cells[cell].active = false
	
	# Remove from active cells list
	var index = active_cells.find(cell)
	if index >= 0:
		active_cells.remove_at(index)
	
	# Signal deactivation
	cell_deactivated.emit(cell)

# Unload a cell completely
func _unload_cell(cell: Vector2i) -> void:
	if not loaded_cells.has(cell):
		return
	
	# If active, deactivate first
	if loaded_cells[cell].active:
		_deactivate_cell(cell)
	
	# Remove cell
	loaded_cells.erase(cell)
	
	# Remove from preloaded cells list if there
	var index = preloaded_cells.find(cell)
	if index >= 0:
		preloaded_cells.remove_at(index)
	
	# Signal unload
	cell_unloaded.emit(cell)

# Generate content for a cell
func _generate_cell_content(cell: Vector2i) -> void:
	# Skip if already generated
	if world_data.is_cell_generated(cell):
		return
	
	# Direct generation through ContentRegistry
	if _content_registry:
		# This just queues the cell for generation
		_content_registry.get_cell_content(cell)
		
		# Mark as generated for immediate use
		world_data.mark_cell_generated(cell)
	else:
		# Fallback (direct generation)
		# TODO: implement direct generation if needed
		pass

# Spawn an entity from data
func _spawn_entity(entity_data: EntityData) -> Node:
	if _spawner_manager and _spawner_manager.has_method("spawn_entity"):
		return _spawner_manager.spawn_entity(entity_data)
	return null

# Helper methods

# Get cells within a radius of a center cell
func _get_cells_in_radius(center: Vector2i, radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if abs(dx) + abs(dy) <= radius:  # Manhattan distance check
				var cell = Vector2i(center.x + dx, center.y + dy)
				if is_valid_cell(cell):
					cells.append(cell)
	
	return cells

# Calculate Manhattan distance between cells
func _calculate_cell_distance(cell1: Vector2i, cell2: Vector2i) -> int:
	return abs(cell1.x - cell2.x) + abs(cell1.y - cell2.y)

# Check if a cell is valid
func is_valid_cell(cell: Vector2i) -> bool:
	if not world_data:
		return false
	return cell.x >= 0 and cell.x < world_data.grid_size and cell.y >= 0 and cell.y < world_data.grid_size

# Convert world position to cell coordinates
func world_to_cell(world_position: Vector2) -> Vector2i:
	if not world_data:
		return Vector2i(-1, -1)
		
	var grid_offset = Vector2(world_data.grid_cell_size * world_data.grid_size / 2.0, 
							 world_data.grid_cell_size * world_data.grid_size / 2.0)
	var local_pos = world_position + grid_offset
	
	return Vector2i(
		int(floor(local_pos.x / world_data.grid_cell_size)),
		int(floor(local_pos.y / world_data.grid_cell_size))
	)

# Convert cell coordinates to world position (center of cell)
func cell_to_world(cell_coords: Vector2i) -> Vector2:
	if not world_data:
		return Vector2.ZERO
		
	var grid_offset = Vector2(world_data.grid_cell_size * world_data.grid_size / 2.0, 
							 world_data.grid_cell_size * world_data.grid_size / 2.0)
	return Vector2(
		cell_coords.x * world_data.grid_cell_size + world_data.grid_cell_size / 2.0,
		cell_coords.y * world_data.grid_cell_size + world_data.grid_cell_size / 2.0
	) - grid_offset

# Get the player entity
func _get_player() -> Node:
	if _entity_manager and _entity_manager.has_method("get_player_ship"):
		return _entity_manager.get_player_ship()
	
	# Fallback
	var players = get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		return players[0]
	
	return null

# Event handlers
func _on_seed_changed(new_seed: int) -> void:
	current_seed = new_seed
	
	# Reset and regenerate world with new seed
	reset_world()
	setup_world(new_seed)
	generate_world()

func _on_content_cache_updated(content_type: String) -> void:
	if content_type == "cell":
		# A cell was generated, check if we need to update
		_update_cell_status()

# Reset world state
func reset_world() -> void:
	# Clear all cells
	var loaded_copy = loaded_cells.keys()
	for cell in loaded_copy:
		_unload_cell(cell)
	
	# Reset tracking
	loaded_cells.clear()
	active_cells.clear()
	preloaded_cells.clear()
	_cells_to_load.clear()
	_cells_to_unload.clear()
	_cells_to_activate.clear()
	_cells_to_deactivate.clear()
	
	# Reset world data
	world_data = null
	
	is_world_loaded = false
	is_world_ready = false

# Public API for direct cell management
func force_load_cell(cell: Vector2i) -> void:
	if not is_valid_cell(cell):
		return
		
	if not loaded_cells.has(cell) and not _cells_to_load.has(cell):
		_cells_to_load.append(cell)
		
func force_activate_cell(cell: Vector2i) -> void:
	if not is_valid_cell(cell):
		return
		
	if not loaded_cells.has(cell):
		_cells_to_load.append(cell)
		_cells_to_activate.append(cell)
	elif not loaded_cells[cell].active and not _cells_to_activate.has(cell):
		_cells_to_activate.append(cell)

func force_deactivate_cell(cell: Vector2i) -> void:
	if loaded_cells.has(cell) and loaded_cells[cell].active and not _cells_to_deactivate.has(cell):
		_cells_to_deactivate.append(cell)

func force_unload_cell(cell: Vector2i) -> void:
	if loaded_cells.has(cell) and not _cells_to_unload.has(cell):
		if loaded_cells[cell].active:
			_cells_to_deactivate.append(cell)
		_cells_to_unload.append(cell)
