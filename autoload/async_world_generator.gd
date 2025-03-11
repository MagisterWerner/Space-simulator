# async_world_generator.gd
# Handles asynchronous generation of world content and provides a high-level
# API for procedural generation that respects the global game seed.
extends "res://autoload/base_service.gd"

signal generation_started(world_type, seed_value)
signal generation_completed(world_type, seed_value)
signal world_entity_generated(entity, entity_type, position)
signal generation_progress(progress_percent, status_message)

# External dependencies
var seed_manager = null
var entity_manager = null
var world_chunk_manager = null
var grid_manager = null
var game_settings = null

# Scene references
var planet_spawner_terran_scene: PackedScene
var planet_spawner_gaseous_scene: PackedScene
var asteroid_field_scene: PackedScene
var station_scene: PackedScene

# Generation state tracking
var _is_generating: bool = false
var _generation_progress: float = 0.0
var _generation_queue: Array = []
var _generated_items: Dictionary = {}
var _player_starting_position: Vector2 = Vector2.ZERO
var _current_world_seed: int = 0

# Generation stats
var _entity_counts: Dictionary = {
	"terran_planet": 0,
	"gaseous_planet": 0,
	"asteroid_field": 0,
	"station": 0
}

# Generation constants
const GENERATION_CHUNK_SIZE: int = 1024
const GENERATION_GRID_SIZE: int = 10
const SEED_OFFSETS = {
	"terran_planet": 100000,
	"gaseous_planet": 200000,
	"asteroid_field": 300000,
	"station": 400000
}

# Generation settings for different world types
const WORLD_TEMPLATES = {
	"starter": {
		"terran_planets": 5,
		"gaseous_planets": 2,
		"asteroid_fields": 10,
		"stations": 3,
		"entity_proximity": {
			"terran_planet": 1,
			"gaseous_planet": 2,
			"asteroid_field": 0,
			"station": 0
		}
	},
	"dense": {
		"terran_planets": 8,
		"gaseous_planets": 4,
		"asteroid_fields": 20,
		"stations": 5,
		"entity_proximity": {
			"terran_planet": 1,
			"gaseous_planet": 1,
			"asteroid_field": 0,
			"station": 0
		}
	},
	"sparse": {
		"terran_planets": 3,
		"gaseous_planets": 1,
		"asteroid_fields": 5,
		"stations": 2,
		"entity_proximity": {
			"terran_planet": 2,
			"gaseous_planet": 3,
			"asteroid_field": 0,
			"station": 0
		}
	}
}

func _ready() -> void:
	# Register self with service locator
	call_deferred("register_self")
	
	# Configure process mode to continue during pause
	process_mode = Node.PROCESS_MODE_ALWAYS

# Return dependencies required by this service
func get_dependencies() -> Array:
	return ["SeedManager", "EntityManager"]

# Initialize this service
func initialize_service() -> void:
	# Get required dependencies
	seed_manager = get_dependency("SeedManager") 
	entity_manager = get_dependency("EntityManager")
	
	# Get optional dependencies
	if has_dependency("WorldChunkManager"):
		world_chunk_manager = get_dependency("WorldChunkManager")
	
	if has_dependency("GridManager"):
		grid_manager = get_dependency("GridManager")
	
	if has_dependency("GameSettings"):
		game_settings = get_dependency("GameSettings")
	
	# Load required scene references
	_load_scene_references()
	
	# Connect to SeedManager signals
	connect_to_dependency("SeedManager", "seed_changed", _on_seed_changed)
	
	# Mark as initialized
	_service_initialized = true
	print("AsyncWorldGenerator: Service initialized successfully")

# Load scene references
func _load_scene_references() -> void:
	# Load planet spawner scenes
	var terran_path = "res://scenes/world/planet_spawner_terran.tscn"
	if ResourceLoader.exists(terran_path):
		planet_spawner_terran_scene = load(terran_path)
	
	var gaseous_path = "res://scenes/world/planet_spawner_gaseous.tscn"
	if ResourceLoader.exists(gaseous_path):
		planet_spawner_gaseous_scene = load(gaseous_path)
	
	# Load asteroid field scene
	var asteroid_path = "res://scenes/world/asteroid_field.tscn"
	if ResourceLoader.exists(asteroid_path):
		asteroid_field_scene = load(asteroid_path)
	
	# Load station scene
	var station_path = "res://scenes/world/station.tscn"
	if ResourceLoader.exists(station_path):
		station_scene = load(station_path)

# Process pending generation tasks async
func _process(delta: float) -> void:
	if not _service_initialized or not _is_generating:
		return
	
	# Process one item from the queue per frame for smooth generation
	if not _generation_queue.is_empty():
		var next_task = _generation_queue.pop_front()
		
		# Execute the task
		match next_task.type:
			"planet_terran":
				_generate_terran_planet(next_task)
			"planet_gaseous":
				_generate_gaseous_planet(next_task)
			"asteroid_field":
				_generate_asteroid_field(next_task)
			"station":
				_generate_station(next_task)
		
		# Update progress
		var task_weight = next_task.get("weight", 1.0)
		_generation_progress += task_weight
		var total_progress = min(100.0, (_generation_progress / next_task.total_weight) * 100.0)
		
		# Emit progress signal
		generation_progress.emit(total_progress, "Generating: " + next_task.type)
	
	# Check if generation is complete
	if _generation_queue.is_empty() and _is_generating:
		_on_generation_complete()

# Handler for completion of world generation
func _on_generation_complete() -> void:
	_is_generating = false
	
	# Emit generation complete signal
	generation_completed.emit("custom", _current_world_seed)
	
	print("AsyncWorldGenerator: World generation complete!")
	print("- Generated %d terran planets" % _entity_counts.terran_planet)
	print("- Generated %d gaseous planets" % _entity_counts.gaseous_planet)
	print("- Generated %d asteroid fields" % _entity_counts.asteroid_field)
	print("- Generated %d stations" % _entity_counts.station)
	
	# If we have a world chunk manager, start loading chunks around player
	if world_chunk_manager and world_chunk_manager.has_method("load_chunks_around_position"):
		world_chunk_manager.load_chunks_around_position(_player_starting_position, 2, 4)

# Generate a procedural world asynchronously
func generate_world_async(world_type: String = "starter", custom_seed: int = -1) -> bool:
	# Skip if already generating
	if _is_generating:
		push_warning("AsyncWorldGenerator: World generation already in progress")
		return false
	
	# Reset state
	_clear_world()
	_reset_generation_state()
	
	# Get world seed
	var seed_value
	if custom_seed >= 0:
		seed_value = custom_seed
	elif seed_manager:
		seed_value = seed_manager.get_seed()
	elif game_settings and game_settings.has_method("get_seed"):
		seed_value = game_settings.get_seed()
	else:
		# Fallback to random seed
		seed_value = randi()
	
	_current_world_seed = seed_value
	
	# Get world template
	var template = WORLD_TEMPLATES.get(world_type, WORLD_TEMPLATES.starter)
	
	# Start generation
	_is_generating = true
	generation_started.emit(world_type, seed_value)
	
	# Calculate total work for progress tracking
	var total_weight = _calculate_total_generation_weight(template)
	
	# Queue generation tasks
	_queue_world_generation_tasks(template, seed_value, total_weight)
	
	return true

# Calculate total work for progress tracking
func _calculate_total_generation_weight(template: Dictionary) -> float:
	var total = 0.0
	
	# Planets take more time to generate
	total += template.terran_planets * 2.0
	total += template.gaseous_planets * 3.0
	
	# Smaller entities are faster
	total += template.asteroid_fields * 0.5
	total += template.stations * 1.0
	
	return total

# Queue generation tasks based on template
func _queue_world_generation_tasks(template: Dictionary, seed_value: int, total_weight: float) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# Mark cells excluded due to proximity
	var excluded_cells = {}
	
	# First, prepare player starting planet (special terran planet)
	var player_cell = _find_random_cell(excluded_cells, rng)
	var player_task = {
		"type": "planet_terran",
		"cell": player_cell,
		"seed": seed_value + SEED_OFFSETS.terran_planet,
		"weight": 2.0,
		"total_weight": total_weight,
		"is_player_start": true
	}
	
	# Mark proximity for player planet
	_mark_proximity_cells(player_cell, template.entity_proximity.terran_planet, excluded_cells)
	
	# Add player planet task first
	_generation_queue.append(player_task)
	
	# Then queue other terran planets (skip the first one as it's the player planet)
	for i in range(1, template.terran_planets):
		var cell = _find_random_cell(excluded_cells, rng)
		if cell == Vector2i(-1, -1):
			# No more valid cells available
			break
			
		_generation_queue.append({
			"type": "planet_terran",
			"cell": cell,
			"seed": seed_value + SEED_OFFSETS.terran_planet + i * 1000,
			"weight": 2.0,
			"total_weight": total_weight
		})
		
		# Mark proximity exclusion
		_mark_proximity_cells(cell, template.entity_proximity.terran_planet, excluded_cells)
	
	# Queue gaseous planets
	for i in range(template.gaseous_planets):
		var cell = _find_random_cell(excluded_cells, rng)
		if cell == Vector2i(-1, -1):
			break
			
		_generation_queue.append({
			"type": "planet_gaseous",
			"cell": cell,
			"seed": seed_value + SEED_OFFSETS.gaseous_planet + i * 1000,
			"weight": 3.0,
			"total_weight": total_weight
		})
		
		# Mark proximity exclusion
		_mark_proximity_cells(cell, template.entity_proximity.gaseous_planet, excluded_cells)
	
	# Queue asteroid fields
	for i in range(template.asteroid_fields):
		var cell = _find_random_cell(excluded_cells, rng)
		if cell == Vector2i(-1, -1):
			break
			
		_generation_queue.append({
			"type": "asteroid_field",
			"cell": cell,
			"seed": seed_value + SEED_OFFSETS.asteroid_field + i * 1000,
			"weight": 0.5,
			"total_weight": total_weight
		})
		
		# Mark proximity exclusion if needed
		if template.entity_proximity.asteroid_field > 0:
			_mark_proximity_cells(cell, template.entity_proximity.asteroid_field, excluded_cells)
	
	# Queue stations
	for i in range(template.stations):
		var cell = _find_random_cell(excluded_cells, rng)
		if cell == Vector2i(-1, -1):
			break
			
		_generation_queue.append({
			"type": "station",
			"cell": cell,
			"seed": seed_value + SEED_OFFSETS.station + i * 1000,
			"weight": 1.0,
			"total_weight": total_weight
		})
		
		# Mark proximity exclusion if needed
		if template.entity_proximity.station > 0:
			_mark_proximity_cells(cell, template.entity_proximity.station, excluded_cells)

# Find a random unoccupied cell
func _find_random_cell(excluded_cells: Dictionary, rng: RandomNumberGenerator) -> Vector2i:
	# Create a list of all possible cells
	var available_cells = []
	var grid_size = GENERATION_GRID_SIZE
	
	if game_settings and "grid_size" in game_settings:
		grid_size = game_settings.grid_size
	
	for x in range(grid_size):
		for y in range(grid_size):
			var cell = Vector2i(x, y)
			var cell_key = _get_cell_key(cell)
			
			if not excluded_cells.has(cell_key):
				available_cells.append(cell)
	
	# Return invalid cell if none available
	if available_cells.is_empty():
		return Vector2i(-1, -1)
	
	# Shuffle the list deterministically
	for i in range(available_cells.size() - 1, 0, -1):
		var j = rng.randi() % (i + 1)
		var temp = available_cells[i]
		available_cells[i] = available_cells[j]
		available_cells[j] = temp
	
	# Return the first cell
	return available_cells[0]

# Mark cells within proximity as excluded
func _mark_proximity_cells(center: Vector2i, proximity: int, excluded_dict: Dictionary) -> void:
	if proximity <= 0:
		# Only exclude the center cell with proximity 0
		excluded_dict[_get_cell_key(center)] = true
		return
	
	# Exclude cells in a square around the center
	for dx in range(-proximity, proximity + 1):
		for dy in range(-proximity, proximity + 1):
			var cell = Vector2i(center.x + dx, center.y + dy)
			
			# Only exclude cells that are within the grid
			if _is_valid_cell(cell):
				excluded_dict[_get_cell_key(cell)] = true

# Get a string key for a cell
func _get_cell_key(cell: Vector2i) -> String:
	return str(cell.x) + "," + str(cell.y)

# Check if a cell is valid (within grid bounds)
func _is_valid_cell(cell: Vector2i) -> bool:
	var grid_size = GENERATION_GRID_SIZE
	
	if game_settings and "grid_size" in game_settings:
		grid_size = game_settings.grid_size
	
	return cell.x >= 0 and cell.x < grid_size and cell.y >= 0 and cell.y < grid_size

# Get world position for a cell
func _get_cell_world_position(cell: Vector2i) -> Vector2:
	var cell_size = GENERATION_CHUNK_SIZE
	var offset = Vector2.ZERO
	
	if game_settings:
		if "grid_cell_size" in game_settings:
			cell_size = game_settings.grid_cell_size
			
		# Centered grid offset if using GameSettings
		var grid_size = game_settings.grid_size if "grid_size" in game_settings else GENERATION_GRID_SIZE
		offset = Vector2(-cell_size * grid_size / 2.0, -cell_size * grid_size / 2.0)
	
	return offset + Vector2(
		cell.x * cell_size + cell_size / 2.0,
		cell.y * cell_size + cell_size / 2.0
	)

# Reset generation state
func _reset_generation_state() -> void:
	_is_generating = false
	_generation_progress = 0.0
	_generation_queue.clear()
	_entity_counts = {
		"terran_planet": 0,
		"gaseous_planet": 0,
		"asteroid_field": 0,
		"station": 0
	}
	_generated_items.clear()

# Clear existing world entities
func _clear_world() -> void:
	# Handle through EntityManager if available
	if entity_manager and entity_manager.has_method("despawn_all"):
		entity_manager.despawn_all()
	
	# Re-initialize tracking
	_generated_items = {
		"planets": [],
		"asteroid_fields": [],
		"stations": []
	}

# Generate a terran planet
func _generate_terran_planet(task: Dictionary) -> void:
	# Skip if terran planet spawner not available
	if not planet_spawner_terran_scene:
		push_error("AsyncWorldGenerator: planet_spawner_terran_scene not loaded")
		return
	
	# Get cell and seed
	var cell = task.cell
	var local_seed = task.seed
	var is_player_start = task.get("is_player_start", false)
	
	# Create the planet spawner
	var planet_spawner = planet_spawner_terran_scene.instantiate()
	add_child(planet_spawner)
	
	# Configure the spawner
	planet_spawner.set_grid_position(cell.x, cell.y)
	planet_spawner.use_grid_position = true
	
	# Set planet type
	var terran_type = 0
	if is_player_start and game_settings and "player_starting_planet_type" in game_settings:
		# Use configured player planet type
		terran_type = game_settings.player_starting_planet_type
	else:
		# Random planet type using SeedManager if available
		if seed_manager:
			terran_type = seed_manager.get_random_int(local_seed, 0, 6)  # 0-6 are terran types
		else:
			# Fallback deterministic approach
			var rng = RandomNumberGenerator.new()
			rng.seed = local_seed
			terran_type = rng.randi_range(0, 6)
	
	# Set planet type (+1 because 0 is Random in the API)
	planet_spawner.terran_theme = terran_type + 1
	
	# Generate seed offset
	var seed_offset = local_seed - _current_world_seed
	planet_spawner.local_seed_offset = seed_offset
	
	# Spawn the planet
	var planet = planet_spawner.spawn_planet()
	
	if not planet:
		push_error("AsyncWorldGenerator: Failed to spawn terran planet at ", cell)
		planet_spawner.queue_free()
		return
	
	# Track this planet
	_generated_items.planets.append(planet_spawner)
	_entity_counts.terran_planet += 1
	
	# If this is the player start planet, remember its position
	if is_player_start:
		_player_starting_position = planet.global_position
		
		# Extra handling for player starting position
		if game_settings and game_settings.has_method("set_player_starting_position"):
			game_settings.set_player_starting_position(planet.global_position)
		
		print("AsyncWorldGenerator: Player starting position set to ", planet.global_position)
	
	# Register with EntityManager
	if entity_manager and entity_manager.has_method("register_entity"):
		entity_manager.register_entity(planet, "planet")
	
	# Emit generation signal
	world_entity_generated.emit(planet, "terran_planet", planet.global_position)

# Generate a gaseous planet
func _generate_gaseous_planet(task: Dictionary) -> void:
	# Skip if gaseous planet spawner not available
	if not planet_spawner_gaseous_scene:
		push_error("AsyncWorldGenerator: planet_spawner_gaseous_scene not loaded")
		return
	
	# Get cell and seed
	var cell = task.cell
	var local_seed = task.seed
	
	# Create the planet spawner
	var planet_spawner = planet_spawner_gaseous_scene.instantiate()
	add_child(planet_spawner)
	
	# Configure the spawner
	planet_spawner.set_grid_position(cell.x, cell.y)
	planet_spawner.use_grid_position = true
	
	# Set planet type
	var gas_giant_type = 0
	if seed_manager:
		gas_giant_type = seed_manager.get_random_int(local_seed, 0, 3)  # 0-3 are gas giant types
	else:
		var rng = RandomNumberGenerator.new()
		rng.seed = local_seed
		gas_giant_type = rng.randi_range(0, 3)
	
	# Set planet type (+1 because 0 is Random in the API)
	planet_spawner.gaseous_theme = gas_giant_type + 1
	
	# Generate seed offset
	var seed_offset = local_seed - _current_world_seed
	planet_spawner.local_seed_offset = seed_offset
	
	# Spawn the planet
	var planet = planet_spawner.spawn_planet()
	
	if not planet:
		push_error("AsyncWorldGenerator: Failed to spawn gaseous planet at ", cell)
		planet_spawner.queue_free()
		return
	
	# Track this planet
	_generated_items.planets.append(planet_spawner)
	_entity_counts.gaseous_planet += 1
	
	# Register with EntityManager
	if entity_manager and entity_manager.has_method("register_entity"):
		entity_manager.register_entity(planet, "planet")
	
	# Emit generation signal
	world_entity_generated.emit(planet, "gaseous_planet", planet.global_position)

# Generate an asteroid field
func _generate_asteroid_field(task: Dictionary) -> void:
	# Skip if asteroid field scene not available
	if not asteroid_field_scene:
		push_error("AsyncWorldGenerator: asteroid_field_scene not loaded")
		return
	
	# Get cell and seed
	var cell = task.cell
	var local_seed = task.seed
	
	# Create the asteroid field
	var asteroid_field = asteroid_field_scene.instantiate()
	add_child(asteroid_field)
	
	# Position the field
	var world_pos = _get_cell_world_position(cell)
	asteroid_field.global_position = world_pos
	
	# Configure the asteroid field if it has the appropriate methods
	if asteroid_field.has_method("generate"):
		# Add some randomization to density and size using SeedManager
		var density = 1.0
		var size = 1.0
		
		if seed_manager:
			density = seed_manager.get_random_value(local_seed, 0.5, 1.5)
			size = seed_manager.get_random_value(local_seed + 1, 0.7, 1.3)
		else:
			var rng = RandomNumberGenerator.new()
			rng.seed = local_seed
			density = rng.randf_range(0.5, 1.5)
			size = rng.randf_range(0.7, 1.3)
		
		asteroid_field.generate(local_seed, density, size)
	
	# Track this asteroid field
	_generated_items.asteroid_fields.append(asteroid_field)
	_entity_counts.asteroid_field += 1
	
	# Register with EntityManager
	if entity_manager and entity_manager.has_method("register_entity"):
		entity_manager.register_entity(asteroid_field, "asteroid_field")
	
	# Emit generation signal
	world_entity_generated.emit(asteroid_field, "asteroid_field", world_pos)

# Generate a station
func _generate_station(task: Dictionary) -> void:
	# Skip if station scene not available
	if not station_scene:
		push_error("AsyncWorldGenerator: station_scene not loaded")
		return
	
	# Get cell and seed
	var cell = task.cell
	var local_seed = task.seed
	
	# Create the station
	var station = station_scene.instantiate()
	add_child(station)
	
	# Position the station
	var world_pos = _get_cell_world_position(cell)
	
	# Add slight position variation within the cell
	var cell_size = GENERATION_CHUNK_SIZE
	if game_settings and "grid_cell_size" in game_settings:
		cell_size = game_settings.grid_cell_size
	
	var offset = Vector2.ZERO
	if seed_manager:
		offset = Vector2(
			seed_manager.get_random_value(local_seed, -cell_size/4.0, cell_size/4.0),
			seed_manager.get_random_value(local_seed + 1, -cell_size/4.0, cell_size/4.0)
		)
	else:
		var rng = RandomNumberGenerator.new()
		rng.seed = local_seed
		offset = Vector2(
			rng.randf_range(-cell_size/4.0, cell_size/4.0),
			rng.randf_range(-cell_size/4.0, cell_size/4.0)
		)
	
	station.global_position = world_pos + offset
	
	# Configure the station if it has an initialize method
	if station.has_method("initialize"):
		station.initialize(local_seed)
	
	# Track this station
	_generated_items.stations.append(station)
	_entity_counts.station += 1
	
	# Register with EntityManager
	if entity_manager and entity_manager.has_method("register_entity"):
		entity_manager.register_entity(station, "station")
	
	# Emit generation signal
	world_entity_generated.emit(station, "station", station.global_position)

# Handle seed changes from SeedManager
func _on_seed_changed(new_seed: int) -> void:
	_current_world_seed = new_seed
	
	# If we're in the middle of generation, stop and start again
	if _is_generating:
		_is_generating = false
		_generation_queue.clear()
		push_warning("AsyncWorldGenerator: Seed changed during generation, restarting...")
		
		# Resume generation with new seed
		generate_world_async("custom", new_seed)

# Public API methods

# Get player starting position
func get_player_starting_position() -> Vector2:
	return _player_starting_position

# Get generation statistics
func get_generation_stats() -> Dictionary:
	return {
		"entities": _entity_counts,
		"progress": _generation_progress,
		"is_generating": _is_generating,
		"seed": _current_world_seed
	}

# Force reseed and regeneration of the world
func regenerate_with_new_seed(new_seed: int = -1) -> bool:
	if new_seed < 0:
		# Generate a random seed if none provided
		new_seed = randi()
	
	# Update SeedManager if available
	if seed_manager:
		seed_manager.set_seed(new_seed)
	elif game_settings and game_settings.has_method("set_seed"):
		game_settings.set_seed(new_seed)
	else:
		_current_world_seed = new_seed
	
	# Start generation
	return generate_world_async("custom", new_seed)

# Clean up threads when scene exits
func _exit_tree() -> void:
	# Just ensure we're not leaving any generation in progress
	_is_generating = false
	_generation_queue.clear()
