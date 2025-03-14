# scripts/managers/world_cell_loader.gd
extends Node
class_name WorldCellLoader

signal cell_loaded(cell_coords)
signal cell_unloaded(cell_coords)

# Configuration
@export var load_radius: int = 2  # Load cells this many steps from player
@export var unload_radius: int = 3  # Unload cells further than this from player
@export var preload_cells: bool = true  # Preload adjacent cells before player arrives
@export var use_content_registry: bool = true  # Use content registry for pre-generated content

# State tracking
var _loaded_cells = {}  # Cell coordinates -> loaded entities
var _player_cell = Vector2i(-1, -1)
var _debug_mode = false
var _game_settings = null

# Manager references
var _grid_manager = null
var _spawner_manager = null
var _content_registry = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Find GameSettings
	var main_scene = get_tree().current_scene
	_game_settings = main_scene.get_node_or_null("GameSettings")
	if _game_settings:
		_debug_mode = _game_settings.debug_mode
	
	# Find GridManager
	if has_node("/root/GridManager"):
		_grid_manager = get_node("/root/GridManager")
		
		# Connect to cell changed signal
		if _grid_manager.has_signal("player_cell_changed") and not _grid_manager.is_connected("player_cell_changed", _on_player_cell_changed):
			_grid_manager.connect("player_cell_changed", _on_player_cell_changed)
	
	# Find ContentRegistry
	if has_node("/root/ContentRegistry"):
		_content_registry = get_node("/root/ContentRegistry")
		
		# Wait for content to be loaded if needed
		if not _content_registry.is_connected("content_loaded", _on_content_loaded):
			_content_registry.connect("content_loaded", _on_content_loaded)
	
	# Get SpawnerManager
	_find_spawner_manager()
	
	# Start monitoring player position
	set_process(true)

func _find_spawner_manager() -> void:
	# Check for direct SpawnerManager autoload
	if has_node("/root/SpawnerManager"):
		_spawner_manager = get_node("/root/SpawnerManager")
		return
	
	# Try to find in scene
	var spawner_managers = get_tree().get_nodes_in_group("spawner_managers")
	if not spawner_managers.is_empty():
		_spawner_manager = spawner_managers[0]
		return
	
	# Create one if needed
	if _debug_mode:
		print("WorldCellLoader: Creating SpawnerManager")
		
	_spawner_manager = SpawnerManager.new()
	_spawner_manager.name = "SpawnerManager"
	add_child(_spawner_manager)

func _on_content_loaded() -> void:
	# Initial cell loading once content is ready
	if _player_cell != Vector2i(-1, -1):
		# Delayed load to ensure everything is ready
		call_deferred("load_cells_around_player")

func _process(_delta: float) -> void:
	# Check if we need to update player position
	update_player_cell()

func update_player_cell() -> void:
	# Try to get player cell from GridManager first
	if _grid_manager and _grid_manager.has_method("get_player_cell"):
		var new_cell = _grid_manager.get_player_cell()
		if new_cell != Vector2i(-1, -1) and new_cell != _player_cell:
			_on_player_cell_changed(_player_cell, new_cell)
			return
	
	# Fallback: find player and calculate cell
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	
	var player = players[0]
	if not is_instance_valid(player):
		return
	
	var player_position = player.global_position
	var new_cell = _position_to_cell(player_position)
	
	if new_cell != _player_cell:
		_on_player_cell_changed(_player_cell, new_cell)

func _on_player_cell_changed(old_cell: Vector2i, new_cell: Vector2i) -> void:
	_player_cell = new_cell
	
	if _debug_mode:
		print("WorldCellLoader: Player moved to cell ", new_cell)
	
	# Load cells around player
	load_cells_around_player()
	
	# Unload distant cells
	unload_distant_cells()

func load_cells_around_player() -> void:
	if _player_cell == Vector2i(-1, -1):
		return
	
	# Get all cells in radius
	var cells_to_load = get_cells_in_radius(_player_cell, load_radius)
	
	for cell in cells_to_load:
		if not _loaded_cells.has(cell):
			load_cell(cell)

func unload_distant_cells() -> void:
	var cells_to_unload = []
	
	# Find cells that are too far
	for cell in _loaded_cells:
		var distance = get_cell_distance(_player_cell, cell)
		if distance > unload_radius:
			cells_to_unload.append(cell)
	
	# Unload cells
	for cell in cells_to_unload:
		unload_cell(cell)

func load_cell(cell: Vector2i) -> void:
	if not _is_valid_cell(cell) or _loaded_cells.has(cell):
		return
	
	if _debug_mode:
		print("WorldCellLoader: Loading cell ", cell)
	
	# Track loaded entities for this cell
	_loaded_cells[cell] = []
	
	# Check content registry for pre-generated content
	if use_content_registry and _content_registry:
		var cell_content = _content_registry.get_world_cell_content(cell)
		if not cell_content.is_empty():
			_load_from_content_registry(cell, cell_content)
			cell_loaded.emit(cell)
			return
	
	# Fallback to procedural generation
	if _spawner_manager:
		_load_procedural_cell(cell)
	
	cell_loaded.emit(cell)

func _load_from_content_registry(cell: Vector2i, content: Dictionary) -> void:
	if not _spawner_manager:
		return
	
	# Spawn each type of content defined in the cell
	if content.has("planets"):
		for planet_data in content.planets:
			var planet = _spawner_manager.spawn_entity(planet_data)
			if planet:
				_loaded_cells[cell].append(planet)
	
	if content.has("asteroid_fields"):
		for field_data in content.asteroid_fields:
			var field = _spawner_manager.spawn_entity(field_data)
			if field:
				_loaded_cells[cell].append(field)
	
	if content.has("stations"):
		for station_data in content.stations:
			var station = _spawner_manager.spawn_entity(station_data)
			if station:
				_loaded_cells[cell].append(station)

func _load_procedural_cell(cell: Vector2i) -> void:
	if not _spawner_manager:
		return
	
	# Determine what to generate in this cell based on position and seed
	var cell_seed = _get_cell_seed(cell)
	var rng = RandomNumberGenerator.new()
	rng.seed = cell_seed
	
	# Probabilities for different entity types
	var planet_chance = 0.2
	var asteroid_field_chance = 0.3
	var station_chance = 0.1
	var empty_chance = 0.4
	
	# Adjust for distance from center
	var distance_from_center = Vector2i(cell.x - 5, cell.y - 5).length()
	if distance_from_center > 3:
		# More asteroids, fewer planets in outer areas
		planet_chance *= (1.0 - min(distance_from_center / 10.0, 0.8))
		asteroid_field_chance *= (1.0 + min(distance_from_center / 8.0, 0.5))
	
	# Generate content based on probabilities
	var roll = rng.randf()
	
	if roll < planet_chance:
		# Spawn planet
		var is_gaseous = rng.randf() < 0.2  # 20% chance for gas giant
		var planet = _spawner_manager.spawn_planet_at_cell(cell, is_gaseous)
		if planet:
			_loaded_cells[cell].append(planet)
	elif roll < planet_chance + asteroid_field_chance:
		# Spawn asteroid field
		var asteroid_field = _spawner_manager.spawn_asteroid_field_at_cell(cell)
		if asteroid_field:
			_loaded_cells[cell].append(asteroid_field)
	elif roll < planet_chance + asteroid_field_chance + station_chance:
		# Spawn station - vary type based on location
		var station_type_roll = rng.randf()
		var station_type = 0  # StationData.StationType.TRADING
		
		if station_type_roll < 0.4:
			station_type = 0  # TRADING
		elif station_type_roll < 0.7:
			station_type = 3  # MINING
		elif station_type_roll < 0.9:
			station_type = 2  # MILITARY
		else:
			station_type = 1  # RESEARCH
		
		var station = _spawner_manager.spawn_station_at_cell(cell, station_type)
		if station:
			_loaded_cells[cell].append(station)

func unload_cell(cell: Vector2i) -> void:
	if not _loaded_cells.has(cell):
		return
	
	if _debug_mode:
		print("WorldCellLoader: Unloading cell ", cell)
	
	# Destroy all entities in this cell
	for entity in _loaded_cells[cell]:
		if is_instance_valid(entity):
			if entity.has_method("queue_free"):
				entity.queue_free()
	
	# Clear cell
	_loaded_cells.erase(cell)
	
	cell_unloaded.emit(cell)

# Pre-load adjacent cells that player might move to
func preload_adjacent_cells() -> void:
	if not preload_cells or _player_cell == Vector2i(-1, -1):
		return
	
	# Get adjacent cells
	var adjacent_cells = get_adjacent_cells(_player_cell)
	
	# Preload each adjacent cell
	for cell in adjacent_cells:
		if not _loaded_cells.has(cell) and _is_valid_cell(cell):
			load_cell(cell)

# Get cells in a given radius
func get_cells_in_radius(center: Vector2i, radius: int) -> Array:
	var cells = []
	
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var cell = Vector2i(center.x + dx, center.y + dy)
			if _is_valid_cell(cell):
				cells.append(cell)
	
	return cells

# Get directly adjacent cells
func get_adjacent_cells(cell: Vector2i) -> Array:
	var adjacent = []
	
	# Cardinal directions
	adjacent.append(Vector2i(cell.x + 1, cell.y))
	adjacent.append(Vector2i(cell.x - 1, cell.y))
	adjacent.append(Vector2i(cell.x, cell.y + 1))
	adjacent.append(Vector2i(cell.x, cell.y - 1))
	
	return adjacent

# Get Manhattan distance between cells
func get_cell_distance(cell_a: Vector2i, cell_b: Vector2i) -> int:
	return abs(cell_a.x - cell_b.x) + abs(cell_a.y - cell_b.y)

# Check if cell is within grid bounds
func _is_valid_cell(cell: Vector2i) -> bool:
	if _grid_manager and _grid_manager.has_method("is_valid_cell"):
		return _grid_manager.is_valid_cell(cell)
	
	# Fallback to default grid size
	var grid_size = 10
	if _game_settings:
		grid_size = _game_settings.grid_size
	
	return cell.x >= 0 and cell.x < grid_size and cell.y >= 0 and cell.y < grid_size

# Convert world position to cell coordinates
func _position_to_cell(position: Vector2) -> Vector2i:
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
	
	var grid_offset = Vector2(cell_size * grid_size / 2.0, cell_size * grid_size / 2.0)
	var local_pos = position + grid_offset
	
	return Vector2i(
		int(floor(local_pos.x / cell_size)),
		int(floor(local_pos.y / cell_size))
	)

# Get deterministic seed for a cell
func _get_cell_seed(cell: Vector2i) -> int:
	var base_seed = 12345
	
	if _game_settings:
		base_seed = _game_settings.get_seed()
	elif has_node("/root/SeedManager"):
		base_seed = SeedManager.get_seed()
	
	return base_seed + (cell.x * 1000) + (cell.y * 100)

# Force load a specific cell
func force_load_cell(cell: Vector2i) -> void:
	if _is_valid_cell(cell) and not _loaded_cells.has(cell):
		load_cell(cell)

# Force unload a specific cell
func force_unload_cell(cell: Vector2i) -> void:
	if _loaded_cells.has(cell):
		unload_cell(cell)

# Get entities in a specific cell
func get_entities_in_cell(cell: Vector2i) -> Array:
	if _loaded_cells.has(cell):
		return _loaded_cells[cell]
	
	return []

# Get entity count
func get_loaded_entity_count() -> int:
	var count = 0
	for cell in _loaded_cells:
		count += _loaded_cells[cell].size()
	
	return count

# Check if a cell is loaded
func is_cell_loaded(cell: Vector2i) -> bool:
	return _loaded_cells.has(cell)
