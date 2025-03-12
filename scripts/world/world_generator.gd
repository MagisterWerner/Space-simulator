extends Node
class_name WorldGenerator

signal world_generation_started
signal world_generation_completed
signal entity_generated(entity, type, cell)

# Cached references
var game_settings: GameSettings = null
var seed_manager = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Scene caching
var _scene_cache = {}
var _planet_cells = []
var _proximity_excluded_cells = {}
var _generated_entities = {}

# Counters for entity types
var _entity_counts = {
	"terran_planet": 0,
	"gaseous_planet": 0,
	"asteroid_field": 0,
	"station": 0
}

# Constants for seeding
const PLANET_SEED_OFFSET = 1000000
const ASTEROID_SEED_OFFSET = 2000000
const STATION_SEED_OFFSET = 3000000
const TERRAN_TYPE_OFFSET = 10000
const GASEOUS_TYPE_OFFSET = 20000

# Precomputed candidate cells
var _all_candidate_cells = []
var _debug_mode = false

func _ready() -> void:
	_find_game_settings()
	_initialize_scenes()

func _find_game_settings() -> void:
	var main_scene = get_tree().current_scene
	game_settings = main_scene.get_node_or_null("GameSettings")
	
	if game_settings:
		if not game_settings.is_connected("debug_settings_changed", _on_debug_settings_changed):
			game_settings.connect("debug_settings_changed", _on_debug_settings_changed)
		
		_debug_mode = game_settings.debug_mode and game_settings.debug_world_generator
		_precalculate_candidate_cells(game_settings.grid_size)
	
	if Engine.has_singleton("SeedManager"):
		seed_manager = Engine.get_singleton("SeedManager")
		
		if not seed_manager.is_initialized and seed_manager.has_signal("seed_initialized"):
			seed_manager.seed_initialized.connect(_on_seed_manager_initialized)

func _on_debug_settings_changed(debug_settings: Dictionary) -> void:
	_debug_mode = debug_settings.get("master", false) and debug_settings.get("world_generator", false)

func _on_seed_manager_initialized() -> void:
	if _debug_mode:
		print("WorldGenerator: SeedManager initialized with seed " + str(seed_manager.get_seed()))

func _initialize_scenes() -> void:
	# Load only the essential scenes initially
	_load_scene("planet_spawner_terran", "res://scenes/world/planet_spawner_terran.tscn")
	_load_scene("planet_spawner_gaseous", "res://scenes/world/planet_spawner_gaseous.tscn")
	_load_scene("asteroid_field", "res://scenes/world/asteroid_field.tscn")
	_load_scene("station", "res://scenes/world/station.tscn")

func _load_scene(key: String, path: String) -> void:
	if _scene_cache.has(key) or not ResourceLoader.exists(path):
		return
	
	_scene_cache[key] = load(path)

func _precalculate_candidate_cells(grid_size: int) -> void:
	_all_candidate_cells.clear()
	for x in range(grid_size):
		for y in range(grid_size):
			_all_candidate_cells.append(Vector2i(x, y))

func generate_starter_world() -> Dictionary:
	clear_world()
	world_generation_started.emit()
	
	_planet_cells.clear()
	_proximity_excluded_cells.clear()
	
	# Generate player starting planet (terran)
	var player_planet_cell = generate_planet("terran_planet", 1, true)
	
	# Generate gaseous planets
	var gaseous_count = game_settings.gaseous_planets if game_settings else 1
	var gaseous_planet_cell = Vector2i(-1, -1)
	
	if gaseous_count > 0:
		gaseous_planet_cell = generate_planet("gaseous_planet", 2)
		
		for i in range(1, gaseous_count):
			generate_planet("gaseous_planet", 2)
	
	# Generate remaining terran planets
	var max_planets = _calculate_max_planets()
	var terran_count = game_settings.terran_planets if game_settings else 5
	
	for i in range(1, terran_count):
		if _entity_counts.terran_planet + _entity_counts.gaseous_planet < max_planets:
			generate_planet("terran_planet", 1)
		else:
			break
	
	# Generate asteroid fields
	var asteroid_count = game_settings.asteroid_fields if game_settings else 0
	for i in range(asteroid_count):
		generate_asteroid_field()
	
	# Generate stations
	var station_count = game_settings.space_stations if game_settings else 0
	for i in range(station_count):
		generate_station()
	
	world_generation_completed.emit()
	
	if _debug_mode:
		_debug_print_summary(player_planet_cell, gaseous_planet_cell, terran_count, gaseous_count, max_planets)
	
	return {
		"player_planet_cell": player_planet_cell,
		"gaseous_planet_cell": gaseous_planet_cell
	}

func _debug_print_summary(player_cell, _gaseous_cell, terran_count, gaseous_count, max_planets) -> void:
	print("WorldGenerator: Generation complete")
	print("- Player planet at cell: " + str(player_cell))
	print("- Total terran planets: " + str(_entity_counts.terran_planet) + "/" + str(terran_count))
	print("- Total gaseous planets: " + str(_entity_counts.gaseous_planet) + "/" + str(gaseous_count))
	print("- Maximum possible planets: " + str(max_planets))
	print("- Total asteroid fields: " + str(_entity_counts.asteroid_field))
	print("- Total stations: " + str(_entity_counts.station))
	print("- Total excluded cells: " + str(_proximity_excluded_cells.size()))

func _calculate_max_planets() -> int:
	var total_cells = game_settings.grid_size * game_settings.grid_size if game_settings else 25
	return total_cells - _proximity_excluded_cells.size()

func _generate_entity_seed(cell: Vector2i, entity_type: String, subtype_index: int = 0) -> int:
	var base_seed
	
	if game_settings:
		base_seed = game_settings.get_seed()
	elif seed_manager:
		base_seed = seed_manager.get_seed()
	else:
		base_seed = get_instance_id()
	
	var type_offset
	match entity_type:
		"terran_planet": type_offset = PLANET_SEED_OFFSET + TERRAN_TYPE_OFFSET
		"gaseous_planet": type_offset = PLANET_SEED_OFFSET + GASEOUS_TYPE_OFFSET
		"asteroid_field": type_offset = ASTEROID_SEED_OFFSET
		"station": type_offset = STATION_SEED_OFFSET
		_: type_offset = 0
	
	return base_seed + type_offset + (cell.x * 1000) + (cell.y * 100) + subtype_index * 10

func _shuffle_candidates(candidate_cells: Array) -> void:
	if seed_manager:
		seed_manager.shuffle_array(candidate_cells, get_instance_id())
	else:
		_rng.seed = game_settings.get_seed() if game_settings else get_instance_id()
		
		# Optimized Fisher-Yates shuffle
		for i in range(candidate_cells.size() - 1, 0, -1):
			var j = _rng.randi_range(0, i)
			if i != j:
				var temp = candidate_cells[i]
				candidate_cells[i] = candidate_cells[j]
				candidate_cells[j] = temp

func get_candidate_cells() -> Array:
	# Filter out excluded cells from precalculated candidates
	var candidates = []
	for cell in _all_candidate_cells:
		if not _proximity_excluded_cells.has(cell):
			candidates.append(cell)
	
	return candidates

func generate_planet(planet_type: String, proximity: int = 1, is_player_starting: bool = false) -> Vector2i:
	var scene_key = "planet_spawner_terran" if planet_type == "terran_planet" else "planet_spawner_gaseous"
	if not _scene_cache.has(scene_key):
		return Vector2i(-1, -1)
	
	var candidate_cells = get_candidate_cells()
	_shuffle_candidates(candidate_cells)
	
	for cell in candidate_cells:
		if is_cell_generated(cell):
			continue
		
		var cell_seed = _generate_entity_seed(cell, planet_type)
		var seed_offset = cell_seed - (game_settings.get_seed() if game_settings else 0)
		
		var planet_spawner = _scene_cache[scene_key].instantiate()
		add_child(planet_spawner)
		
		# Determine planet type
		var planet_type_value
		
		if planet_type == "terran_planet" and is_player_starting and game_settings:
			planet_type_value = game_settings.player_starting_planet_type
		else:
			if seed_manager:
				planet_type_value = seed_manager.get_random_int(cell_seed, 0, 6 if planet_type == "terran_planet" else 3)
			else:
				_rng.seed = cell_seed
				planet_type_value = _rng.randi_range(0, 6 if planet_type == "terran_planet" else 3)
				
			# Avoid duplicating player starting planet type
			if planet_type == "terran_planet" and game_settings and planet_type_value == game_settings.player_starting_planet_type:
				planet_type_value = (planet_type_value + 1) % 7
		
		# Configure spawner
		if planet_type == "terran_planet":
			planet_spawner.terran_theme = planet_type_value + 1
		else:
			planet_spawner.gaseous_theme = planet_type_value + 1
		
		planet_spawner.set_grid_position(cell.x, cell.y)
		planet_spawner.use_grid_position = true
		planet_spawner.local_seed_offset = seed_offset
		
		var planet = planet_spawner.spawn_planet()
		
		if not planet:
			planet_spawner.queue_free()
			continue
		
		# Store generated entity
		_register_generated_entity(cell, planet_spawner, "planet_spawner")
		_entity_counts[planet_type] += 1
		
		# Connect to planet spawned signal
		if planet_spawner.has_signal("planet_spawned") and not planet_spawner.is_connected("planet_spawned", _on_planet_spawned):
			planet_spawner.planet_spawned.connect(_on_planet_spawned)
		
		mark_proximity_cells(cell, proximity)
		_planet_cells.append(cell)
		
		entity_generated.emit(planet, planet_type, cell)
		
		if _debug_mode and planet_type == "terran_planet" and is_player_starting:
			print("WorldGenerator: Generated player starting planet (" + 
				game_settings.get_planet_type_name(planet_type_value) + ") at " + str(cell))
		
		return cell
	
	if _debug_mode:
		print("WorldGenerator: Failed to generate " + planet_type + " - no valid cells available")
	
	return Vector2i(-1, -1)

func generate_asteroid_field() -> Vector2i:
	if not _scene_cache.has("asteroid_field"):
		return Vector2i(-1, -1)
	
	var candidate_cells = get_candidate_cells()
	_shuffle_candidates(candidate_cells)
	
	for cell in candidate_cells:
		if is_cell_generated(cell):
			continue
			
		var field_seed = _generate_entity_seed(cell, "asteroid_field")
		
		var asteroid_field = _scene_cache["asteroid_field"].instantiate()
		add_child(asteroid_field)
		
		var world_pos = _cell_to_world_position(cell)
		asteroid_field.global_position = world_pos
		
		if asteroid_field.has_method("generate"):
			var density = 1.0
			var size = 1.0
			
			if seed_manager:
				density = seed_manager.get_random_value(field_seed, 0.5, 1.5)
				size = seed_manager.get_random_value(field_seed + 1, 0.7, 1.3)
			else:
				_rng.seed = field_seed
				density = _rng.randf_range(0.5, 1.5)
				size = _rng.randf_range(0.7, 1.3)
			
			asteroid_field.generate(field_seed, density, size)
		
		_register_generated_entity(cell, asteroid_field, "asteroid_field")
		_entity_counts.asteroid_field += 1
		
		if has_node("/root/EntityManager") and EntityManager.has_method("register_entity"):
			EntityManager.register_entity(asteroid_field, "asteroid_field")
		
		entity_generated.emit(asteroid_field, "asteroid_field", cell)
		
		return cell
	
	if _debug_mode:
		print("WorldGenerator: Failed to generate asteroid field - no valid cells available")
	
	return Vector2i(-1, -1)

func generate_station() -> Vector2i:
	if not _scene_cache.has("station"):
		return Vector2i(-1, -1)
	
	var candidate_cells = get_candidate_cells()
	_shuffle_candidates(candidate_cells)
	
	for cell in candidate_cells:
		if is_cell_generated(cell):
			continue
			
		var station_seed = _generate_entity_seed(cell, "station")
		
		var station = _scene_cache["station"].instantiate()
		add_child(station)
		
		var world_pos = _cell_to_world_position(cell)
		
		# Add a deterministic offset
		var offset = Vector2.ZERO
		var cell_size = game_settings.grid_cell_size if game_settings else 1024
		
		if seed_manager:
			offset = Vector2(
				seed_manager.get_random_value(station_seed, -cell_size/4.0, cell_size/4.0),
				seed_manager.get_random_value(station_seed + 1, -cell_size/4.0, cell_size/4.0)
			)
		else:
			_rng.seed = station_seed
			offset = Vector2(
				_rng.randf_range(-cell_size/4.0, cell_size/4.0),
				_rng.randf_range(-cell_size/4.0, cell_size/4.0)
			)
			
		station.global_position = world_pos + offset
		
		if station.has_method("initialize"):
			station.initialize(station_seed)
		
		_register_generated_entity(cell, station, "station")
		_entity_counts.station += 1
		
		if has_node("/root/EntityManager") and EntityManager.has_method("register_entity"):
			EntityManager.register_entity(station, "station")
		
		entity_generated.emit(station, "station", cell)
		
		return cell
	
	if _debug_mode:
		print("WorldGenerator: Failed to generate station - no valid cells available")
	
	return Vector2i(-1, -1)

func _on_planet_spawned(planet_instance) -> void:
	if has_node("/root/EntityManager") and EntityManager.has_method("register_entity"):
		EntityManager.register_entity(planet_instance, "planet")

func mark_proximity_cells(center: Vector2i, proximity: int) -> void:
	if proximity <= 0:
		_proximity_excluded_cells[center] = true
		return
	
	# Optimized proximity marking - only process required cells
	for dx in range(-proximity, proximity + 1):
		for dy in range(-proximity, proximity + 1):
			var cell = Vector2i(center.x + dx, center.y + dy)
			if is_valid_cell(cell):
				_proximity_excluded_cells[cell] = true

func clear_world() -> void:
	for cell in _generated_entities:
		var cell_data = _generated_entities[cell]
		
		for entity_type in cell_data:
			for entity in cell_data[entity_type]:
				if is_instance_valid(entity):
					if has_node("/root/EntityManager") and EntityManager.has_method("deregister_entity") and entity_type != "planet_spawner":
						EntityManager.deregister_entity(entity)
					entity.queue_free()
	
	_generated_entities.clear()
	_entity_counts = {
		"terran_planet": 0,
		"gaseous_planet": 0,
		"asteroid_field": 0,
		"station": 0
	}
	
	_planet_cells.clear()
	_proximity_excluded_cells.clear()
	
	if _debug_mode:
		print("WorldGenerator: World cleared")

func is_valid_cell(cell_coords: Vector2i) -> bool:
	var grid_size = game_settings.grid_size if game_settings else 5
	return (
		cell_coords.x >= 0 and cell_coords.x < grid_size and
		cell_coords.y >= 0 and cell_coords.y < grid_size
	)

func is_cell_generated(cell_coords: Vector2i) -> bool:
	return _generated_entities.has(cell_coords)

func _register_generated_entity(cell: Vector2i, entity: Node, entity_type: String) -> void:
	if not _generated_entities.has(cell):
		_generated_entities[cell] = {}
	
	if not _generated_entities[cell].has(entity_type):
		_generated_entities[cell][entity_type] = []
	
	_generated_entities[cell][entity_type].append(entity)

func _cell_to_world_position(cell: Vector2i) -> Vector2:
	if game_settings:
		return game_settings.get_cell_world_position(cell)
	else:
		var cell_size = 1024  # Default
		return Vector2(cell.x * cell_size + cell_size/2.0, cell.y * cell_size + cell_size/2.0)

func get_cell_entities(cell_coords: Vector2i) -> Array:
	if not _generated_entities.has(cell_coords):
		return []
		
	var result = []
	var cell_data = _generated_entities[cell_coords]
	
	for entity_type in cell_data:
		for entity in cell_data[entity_type]:
			if is_instance_valid(entity):
				if entity_type == "planet_spawner" and entity.has_method("get_planet_instance"):
					var planet = entity.get_planet_instance()
					if planet:
						result.append(planet)
				else:
					result.append(entity)
	
	return result
