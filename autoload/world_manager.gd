extends Node

# ----- SIGNALS -----
# World lifecycle signals
signal world_ready
signal player_ready
signal world_generation_completed

# Cell management signals
signal cell_loaded(cell_coords)
signal cell_unloaded(cell_coords)
signal player_cell_changed(old_cell, new_cell)

# Entity signals
signal entity_spawned(entity, entity_data)
signal entity_despawned(entity, entity_data)

# Seed management
signal seed_initialized
signal seed_changed(new_seed)

# ----- CONFIGURATION -----
# Cell management settings
@export var active_cell_radius: int = 2  # Cells around player to keep loaded
@export var preload_cell_radius: int = 3  # Cells to preload data for
@export var unload_distance: int = 4     # When to unload distant cells
@export var max_cells_per_frame: int = 2 # Maximum cells to process per frame

# Grid settings
@export var cell_size: int = 1024        # Size of each cell in pixels
@export var grid_size: int = 10          # Grid dimensions (cells per side)

# ----- WORLD STATE -----
# Core world data
var world_data: WorldData = null
var is_world_loaded: bool = false
var current_seed: int = 0

# Cell tracking
var loaded_cells = {}  # Vector2i -> { entities: [], active: bool, entity_data: [], initialized: bool }
var active_cells = []
var preloaded_cells = []
var current_player_cell = Vector2i(-1, -1)

# Processing queues
var _cells_to_load = []
var _cells_to_unload = []

# ----- MANAGER REFERENCES -----
var _entity_manager = null
var _spawner_manager = null
var _game_settings = null
var _game_manager = null

# ----- INTERNAL STATE -----
var _initialized: bool = false
var _processing_enabled: bool = true
var _debug_mode: bool = false
var _seed_ready: bool = false
var _player_last_position: Vector2 = Vector2.ZERO

# Generator reference
var world_generator = null

func _ready() -> void:
	# Add to groups for easy access
	add_to_group("world_manager")
	add_to_group("world_simulation")
	add_to_group("world_grid")
	
	# Find manager references
	_find_managers()
	
	# Create world generator
	_create_world_generator()
	
	# Find game settings for configuration
	_find_game_settings()
	
	# Initialize after engine is ready
	call_deferred("_initialize_systems")

func _find_managers() -> void:
	_entity_manager = get_node_or_null("/root/EntityManager")
	_game_manager = get_node_or_null("/root/GameManager")
	
	# Find spawner manager - try to get from scene first
	_spawner_manager = get_node_or_null("/root/SpawnerManager")
	if not _spawner_manager:
		var spawners = get_tree().get_nodes_in_group("spawner_managers")
		if not spawners.is_empty():
			_spawner_manager = spawners[0]

func _find_game_settings() -> void:
	# Find GameSettings
	var main_scene = get_tree().current_scene
	_game_settings = main_scene.get_node_or_null("GameSettings")
	
	if _game_settings:
		# Update settings from GameSettings
		_debug_mode = _game_settings.debug_mode
		cell_size = _game_settings.grid_cell_size
		grid_size = _game_settings.grid_size
		
		# Connect to GameSettings for seed changes
		if _game_settings.has_signal("seed_changed"):
			if not _game_settings.is_connected("seed_changed", _on_seed_changed):
				_game_settings.connect("seed_changed", _on_seed_changed)
	
	# Connect to SeedManager
	_connect_to_seed_manager()

func _create_world_generator() -> void:
	# Create world generator if it doesn't exist
	if not world_generator:
		# Check if the class is already available
		if ClassDB.class_exists("WorldGenerator"):
			# Create using the engine class
			world_generator = WorldGenerator.new()
		elif ResourceLoader.exists("res://scripts/generators/world_generator.gd"):
			# Load the script and create an instance
			var WorldGeneratorScript = load("res://scripts/generators/world_generator.gd")
			world_generator = WorldGeneratorScript.new(current_seed)
		else:
			# Create an instance of our just-created class
			world_generator = WorldGenerator.new(current_seed)
		
		world_generator.name = "WorldGenerator"
		add_child(world_generator)
		
		# Connect to world generator signals
		if world_generator.has_signal("world_generation_completed"):
			world_generator.connect("world_generation_completed", _on_world_generation_completed)

func _initialize_systems() -> void:
	# Start processing
	set_process(true)
	
	_initialized = true

func _connect_to_seed_manager() -> void:
	if has_node("/root/SeedManager"):
		# Connect to seed changes
		if SeedManager.has_signal("seed_changed") and not SeedManager.is_connected("seed_changed", _on_seed_changed):
			SeedManager.connect("seed_changed", _on_seed_changed)
		
		# Wait for initialization if needed
		if SeedManager.has_method("is_initialized") and not SeedManager.is_initialized:
			if SeedManager.has_signal("seed_initialized"):
				SeedManager.seed_initialized.connect(_on_seed_manager_initialized)
		else:
			_seed_ready = true
			current_seed = SeedManager.get_seed()
	elif _game_settings:
		_seed_ready = true
		current_seed = _game_settings.get_seed()

func _on_seed_manager_initialized() -> void:
	_seed_ready = true
	if has_node("/root/SeedManager"):
		current_seed = SeedManager.get_seed()
	
	seed_initialized.emit()

func _on_seed_changed(new_seed) -> void:
	current_seed = new_seed
	_seed_ready = true
	seed_changed.emit(new_seed)

func _process(_delta: float) -> void:
	if not _processing_enabled or not _initialized:
		return
	
	# Check player position to update current cell
	_update_player_cell()
	
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

func _update_player_cell() -> void:
	var player_ships = get_tree().get_nodes_in_group("player")
	if player_ships.is_empty():
		return
	
	var player_ship = player_ships[0]
	var player_position = player_ship.global_position
	
	# Only check if player has moved significantly
	if player_position.distance_to(_player_last_position) < cell_size / 4.0:
		return
	
	_player_last_position = player_position
	
	# Calculate cell coordinates
	var cell_coords = world_to_cell(player_position)
	
	# Check if cell changed
	if cell_coords != current_player_cell:
		var old_cell = current_player_cell
		current_player_cell = cell_coords
		player_cell_changed.emit(old_cell, current_player_cell)
		
		# Update cell loading
		_update_cell_status()

# ----- WORLD LOADING AND GENERATION -----

# Load a world from WorldData
func load_world(data: WorldData) -> bool:
	if not _entity_manager or not _spawner_manager:
		push_error("WorldManager: Cannot load world - missing managers")
		return false
	
	world_data = data
	
	if _debug_mode:
		print("WorldManager: Loading world with seed " + str(world_data.seed_value))
	
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
		current_player_cell = Vector2i(grid_size / 2, grid_size / 2)
	
	# Queue cells for preloading and activation
	_update_cell_status()
	
	is_world_loaded = true
	world_ready.emit()
	
	return true

# Generate a new world
func generate_world(seed_value: int = 0) -> WorldData:
	if _debug_mode:
		print("WorldManager: Generating new world with seed " + str(seed_value))
	
	# Update seed manager if available
	if has_node("/root/SeedManager"):
		SeedManager.set_seed(seed_value)
	
	current_seed = seed_value
	
	# Generate world data
	world_data = world_generator.generate_world_data(seed_value)
	
	return world_data

# Create and load a world with a specific seed
func create_and_load_world(seed_value: int = 0) -> bool:
	# Generate the world
	var data = generate_world(seed_value)
	
	# Load the generated world
	return load_world(data)

# Save current world state
func save_world_state(filepath: String = "user://world.save") -> Error:
	if not world_data:
		return ERR_UNAVAILABLE
	
	# Update world data from active entities
	_update_world_data_from_entities()
	
	# Save to file
	return world_data.save_to_file(filepath)

# Load world state from file
func load_world_state(filepath: String = "user://world.save") -> Error:
	if not FileAccess.file_exists(filepath):
		push_error("WorldManager: File not found: " + filepath)
		return ERR_FILE_NOT_FOUND
	
	# Load from file
	var data = WorldData.load_from_file(filepath)
	if not data:
		push_error("WorldManager: Failed to load world data from file")
		return ERR_FILE_CANT_READ
	
	# Store the data
	world_data = data
	
	# Update seed
	if has_node("/root/SeedManager"):
		SeedManager.set_seed(data.seed_value)
	
	current_seed = data.seed_value
	
	# Load into simulation
	if not load_world(data):
		push_error("WorldManager: Failed to load world")
		return ERR_CANT_CREATE
	
	return OK

func _on_world_generation_completed() -> void:
	if _debug_mode:
		print("WorldManager: World generation completed")
	
	world_generation_completed.emit()

# ----- CELL MANAGEMENT -----

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
	if not is_valid_cell(cell) or loaded_cells.has(cell):
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
	
	# Gather entity data from world_data
	var cell_entities = []
	
	if world_data:
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
		print("WorldManager: Preloaded cell " + str(cell) + " with " + str(cell_entities.size()) + " entities")

# Load and activate a cell
func _load_cell(cell: Vector2i) -> void:
	if not is_valid_cell(cell):
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
		print("WorldManager: Activating cell " + str(cell))
	
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
		print("WorldManager: Deactivating cell " + str(cell))
	
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
		print("WorldManager: Unloading cell " + str(cell))
	
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
				if is_valid_cell(cell):
					cells.append(cell)
	
	return cells

# Calculate Manhattan distance between cells
func _calculate_cell_distance(cell1: Vector2i, cell2: Vector2i) -> int:
	return abs(cell1.x - cell2.x) + abs(cell1.y - cell2.y)

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

# ----- GRID FUNCTIONS -----

# Convert world position to cell coordinates
func world_to_cell(world_position: Vector2) -> Vector2i:
	var grid_offset = Vector2(-cell_size * grid_size / 2.0, -cell_size * grid_size / 2.0)
	var local_pos = world_position - grid_offset
	
	return Vector2i(
		int(floor(local_pos.x / cell_size)),
		int(floor(local_pos.y / cell_size))
	)

# Convert cell coordinates to world position (center of cell)
func cell_to_world(cell_coords: Vector2i) -> Vector2:
	var grid_offset = Vector2(-cell_size * grid_size / 2.0, -cell_size * grid_size / 2.0)
	return grid_offset + Vector2(
		cell_coords.x * cell_size + cell_size / 2.0,
		cell_coords.y * cell_size + cell_size / 2.0
	)

# Check if a cell is valid
func is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < grid_size and cell.y >= 0 and cell.y < grid_size

# Get neighboring cell coordinates
func get_neighbor_cells(cell_coords: Vector2i, include_diagonals: bool = false) -> Array:
	var neighbors = []
	
	# Cardinal directions
	var directions = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]
	
	# Add diagonals if requested
	if include_diagonals:
		directions.append_array([
			Vector2i(1, 1),
			Vector2i(1, -1),
			Vector2i(-1, 1),
			Vector2i(-1, -1)
		])
	
	# Check each direction
	for dir in directions:
		var neighbor = cell_coords + dir
		if is_valid_cell(neighbor):
			neighbors.append(neighbor)
	
	return neighbors

# Get cell value based on seed (deterministic)
func get_cell_value(cell_coords: Vector2i, min_val: float, max_val: float, parameter_id: int = 0) -> float:
	# Use SeedManager if available
	if has_node("/root/SeedManager"):
		var object_id = cell_coords.x * 10000 + cell_coords.y
		return SeedManager.get_random_value(object_id, min_val, max_val, parameter_id)
	
	# Fallback to direct calculation
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(str(current_seed) + str(cell_coords) + str(parameter_id))
	return min_val + rng.randf() * (max_val - min_val)

# Get deterministic integer for a cell
func get_cell_int(cell_coords: Vector2i, min_val: int, max_val: int, parameter_id: int = 0) -> int:
	# Use SeedManager if available
	if has_node("/root/SeedManager"):
		var object_id = cell_coords.x * 10000 + cell_coords.y
		return SeedManager.get_random_int(object_id, min_val, max_val, parameter_id)
	
	# Fallback to direct calculation
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(str(current_seed) + str(cell_coords) + str(parameter_id))
	return rng.randi_range(min_val, max_val)

# ----- PUBLIC API -----

# Get player's current cell coordinates
func get_player_cell() -> Vector2i:
	return current_player_cell

# Force load a specific cell
func load_cell(cell: Vector2i) -> void:
	if is_valid_cell(cell) and not loaded_cells.has(cell) and not _cells_to_load.has(cell):
		_cells_to_load.append(cell)

# Force activate a specific cell
func activate_cell(cell: Vector2i) -> void:
	if is_valid_cell(cell) and loaded_cells.has(cell) and not loaded_cells[cell].active:
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

# Get world data
func get_world_data() -> WorldData:
	return world_data

# Is world ready for game to start?
func is_world_ready() -> bool:
	return is_world_loaded

# Set the player's start position
func set_player_start_position(position: Vector2, cell: Vector2i = Vector2i(-1, -1)) -> void:
	if cell == Vector2i(-1, -1):
		cell = world_to_cell(position)
	
	if world_data:
		world_data.player_start_position = position
		world_data.player_start_cell = cell

# Pause/resume cell processing
func set_processing_enabled(enabled: bool) -> void:
	_processing_enabled = enabled

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
	
	# Reset world data
	world_data = null
	
	is_world_loaded = false

# Clear all cells (useful for scene transitions)
func clear_all_cells() -> void:
	reset_world()
