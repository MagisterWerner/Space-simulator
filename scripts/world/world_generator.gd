extends Node
class_name WorldGenerator

signal world_generation_started
signal world_generation_completed
signal entity_generated(entity, type, cell)

# Cached references
var game_settings: GameSettings = null
var seed_manager = null

# Entity generation
const ENTITY_TYPES = {
	"TERRAN_PLANET": "terran_planet",
	"GASEOUS_PLANET": "gaseous_planet",
	"ASTEROID_FIELD": "asteroid_field",
	"STATION": "station"
}

# Scene caching
var _scene_cache = {}
var _generated_entities = {}
var _entity_counts = {}
var _planet_cells = []
var _excluded_cells = {}
var _all_candidate_cells = []
var _debug_mode = false

# Constants for efficient seeding
const PLANET_SEED_OFFSET = 1000000
const ASTEROID_SEED_OFFSET = 2000000
const STATION_SEED_OFFSET = 3000000
const TERRAN_TYPE_OFFSET = 10000
const GASEOUS_TYPE_OFFSET = 20000

# Generation IDs to replace instance IDs
var _generation_id: int = 0

func _ready() -> void:
	_initialize()
	
func _initialize() -> void:
	# Reset entity counts and generation ID
	_generation_id = 0
	
	for type in ENTITY_TYPES.values():
		_entity_counts[type] = 0
	
	# Find game settings
	var main_scene = get_tree().current_scene
	game_settings = main_scene.get_node_or_null("GameSettings")
	
	if game_settings:
		_debug_mode = game_settings.debug_mode and game_settings.debug_world_generator
		_debug_mode = game_settings.get_debug_status("world_generator")
		var grid_size = game_settings.grid_size
		_precalculate_candidate_cells(grid_size)
		
		# Connect to debug settings changes
		if not game_settings.is_connected("debug_settings_changed", _on_debug_settings_changed):
			game_settings.connect("debug_settings_changed", _on_debug_settings_changed)
	
	# Connect to SeedManager synchronously
	seed_manager = get_node_or_null("/root/SeedManager")
	
	# Load essential scenes
	_load_essential_scenes()

func _on_debug_settings_changed(debug_settings: Dictionary) -> void:
	_debug_mode = debug_settings.get("master", false) and debug_settings.get("world_generator", false)

func _on_seed_manager_initialized() -> void:
	# Reset to ensure deterministic generation
	_generation_id = 0

func _load_essential_scenes() -> void:
	_load_scene("planet_spawner_terran", "res://scenes/world/planet_spawner_terran.tscn")
	_load_scene("planet_spawner_gaseous", "res://scenes/world/planet_spawner_gaseous.tscn")
	_load_scene("asteroid_field", "res://scenes/world/asteroid_field.tscn")
	_load_scene("station", "res://scenes/world/station.tscn")

func _load_scene(key: String, path: String) -> void:
	if _scene_cache.has(key):
		return
		
	if not ResourceLoader.exists(path):
		push_error("WorldGenerator: Scene file does not exist: " + path)
		return
		
	_scene_cache[key] = load(path)

func _precalculate_candidate_cells(grid_size: int) -> void:
	_all_candidate_cells.clear()
	for x in range(grid_size):
		for y in range(grid_size):
			_all_candidate_cells.append(Vector2i(x, y))

func generate_starter_world() -> Dictionary:
	# Reset generation ID to ensure determinism
	_generation_id = 0
	
	# Clear previous generation
	clear_world()
	
	if _debug_mode:
		print("WorldGenerator: Starting world generation with seed: ", game_settings.get_seed())
	
	world_generation_started.emit()
	
	# Generate the player's starting planet (terran)
	var player_planet_cell = generate_entity(ENTITY_TYPES.TERRAN_PLANET, {
		"proximity": 1,
		"is_player_starting": true
	})
	
	# Generate gaseous planets
	var gaseous_count = game_settings.gaseous_planets if game_settings else 1
	var gaseous_planet_cell = Vector2i(-1, -1)
	
	if gaseous_count > 0:
		gaseous_planet_cell = generate_entity(ENTITY_TYPES.GASEOUS_PLANET, {
			"proximity": 2
		})
		
		# Generate remaining gaseous planets
		for i in range(1, gaseous_count):
			generate_entity(ENTITY_TYPES.GASEOUS_PLANET, {
				"proximity": 2
			})
	
	# Generate remaining terran planets
	var max_planets = _calculate_max_planets()
	var terran_count = game_settings.terran_planets if game_settings else 5
	
	for i in range(1, terran_count):
		if _entity_counts[ENTITY_TYPES.TERRAN_PLANET] + _entity_counts[ENTITY_TYPES.GASEOUS_PLANET] < max_planets:
			generate_entity(ENTITY_TYPES.TERRAN_PLANET, {
				"proximity": 1
			})
		else:
			break
	
	# Generate asteroid fields
	var asteroid_count = game_settings.asteroid_fields if game_settings else 0
	_batch_generate_entities(ENTITY_TYPES.ASTEROID_FIELD, asteroid_count)
	
	# Generate stations
	var station_count = game_settings.space_stations if game_settings else 0
	_batch_generate_entities(ENTITY_TYPES.STATION, station_count)
	
	world_generation_completed.emit()
	
	if _debug_mode:
		print("WorldGenerator: World generation completed")
		print("Planets generated: ", 
			_entity_counts[ENTITY_TYPES.TERRAN_PLANET] + _entity_counts[ENTITY_TYPES.GASEOUS_PLANET])
		print("Asteroid fields generated: ", _entity_counts[ENTITY_TYPES.ASTEROID_FIELD])
		print("Stations generated: ", _entity_counts[ENTITY_TYPES.STATION])
	
	return {
		"player_planet_cell": player_planet_cell,
		"gaseous_planet_cell": gaseous_planet_cell
	}

func _batch_generate_entities(entity_type: String, count: int, params: Dictionary = {}) -> Array:
	var generated_cells = []
	
	for i in range(count):
		var cell = generate_entity(entity_type, params)
		if cell != Vector2i(-1, -1):
			generated_cells.append(cell)
			
	return generated_cells

func _calculate_max_planets() -> int:
	var total_cells = game_settings.grid_size * game_settings.grid_size if game_settings else 25
	return min(total_cells - _excluded_cells.size(), 15)  # Cap at 15 to avoid overcrowding

func generate_entity(entity_type: String, params: Dictionary = {}) -> Vector2i:
	# Increment generation ID for deterministic ordering
	_generation_id += 1
	
	# Get scene key based on entity type
	var scene_key = _get_scene_key_for_entity(entity_type)
	if not _scene_cache.has(scene_key):
		if _debug_mode:
			print("WorldGenerator: Error - Scene not found in cache: ", scene_key)
		return Vector2i(-1, -1)
	
	# Process parameters
	var proximity = params.get("proximity", 1)
	var is_player_starting = params.get("is_player_starting", false)
	
	# Get valid candidate cells
	var candidate_cells = get_candidate_cells()
	if candidate_cells.is_empty():
		if _debug_mode:
			print("WorldGenerator: Error - No valid cells available for entity: ", entity_type)
		return Vector2i(-1, -1)
	
	# Shuffle deterministically using current seed and generation ID
	_shuffle_candidates_deterministic(candidate_cells)
	
	# Try to find a valid cell for generation
	for cell in candidate_cells:
		if is_cell_generated(cell):
			continue
		
		var entity_seed = _generate_entity_seed(cell, entity_type)
		var entity_instance = null
		
		match entity_type:
			ENTITY_TYPES.TERRAN_PLANET, ENTITY_TYPES.GASEOUS_PLANET:
				entity_instance = _generate_planet(entity_type, cell, entity_seed, is_player_starting)
			ENTITY_TYPES.ASTEROID_FIELD:
				entity_instance = _generate_asteroid_field(cell, entity_seed)
			ENTITY_TYPES.STATION:
				entity_instance = _generate_station(cell, entity_seed)
		
		if entity_instance:
			_entity_counts[entity_type] += 1
			entity_generated.emit(entity_instance, entity_type, cell)
			
			# Mark surrounding cells as excluded
			mark_proximity_cells(cell, proximity)
			
			if entity_type == ENTITY_TYPES.TERRAN_PLANET or entity_type == ENTITY_TYPES.GASEOUS_PLANET:
				_planet_cells.append(cell)
			
			if _debug_mode:
				print("Generated ", entity_type, " at cell ", cell, " with seed ", entity_seed)
			
			return cell
	
	if _debug_mode:
		print("WorldGenerator: Failed to find valid location for entity: ", entity_type)
	return Vector2i(-1, -1)

func _get_scene_key_for_entity(entity_type: String) -> String:
	match entity_type:
		ENTITY_TYPES.TERRAN_PLANET: return "planet_spawner_terran"
		ENTITY_TYPES.GASEOUS_PLANET: return "planet_spawner_gaseous"
		ENTITY_TYPES.ASTEROID_FIELD: return "asteroid_field"
		ENTITY_TYPES.STATION: return "station"
		_: return ""

func _generate_planet(planet_type: String, cell: Vector2i, cell_seed: int, is_player_starting: bool) -> Node:
	var scene_key = "planet_spawner_terran" if planet_type == ENTITY_TYPES.TERRAN_PLANET else "planet_spawner_gaseous"
	var seed_offset = cell_seed - (game_settings.get_seed() if game_settings else 0)
	
	var planet_spawner = _scene_cache[scene_key].instantiate()
	add_child(planet_spawner)
	
	# Deterministic generation of planet type
	var planet_type_value
	
	if planet_type == ENTITY_TYPES.TERRAN_PLANET and is_player_starting and game_settings:
		planet_type_value = game_settings.get_effective_planet_type()
	else:
		# Create deterministic planet type based on cell and seed
		var planet_type_seed = cell_seed * 10 + (1 if planet_type == ENTITY_TYPES.TERRAN_PLANET else 2)
		
		if seed_manager:
			planet_type_value = seed_manager.get_random_int(planet_type_seed, 0, 6 if planet_type == ENTITY_TYPES.TERRAN_PLANET else 3)
		else:
			var rng = RandomNumberGenerator.new()
			rng.seed = planet_type_seed
			planet_type_value = rng.randi_range(0, 6 if planet_type == ENTITY_TYPES.TERRAN_PLANET else 3)
			
		# Avoid duplicating player starting planet type
		if planet_type == ENTITY_TYPES.TERRAN_PLANET and game_settings and planet_type_value == game_settings.get_effective_planet_type():
			planet_type_value = (planet_type_value + 1) % 7
	
	# Add to planet_spawners group for cache clearing
	if not planet_spawner.is_in_group("planet_spawners"):
		planet_spawner.add_to_group("planet_spawners")
	
	# Configure spawner
	if planet_type == ENTITY_TYPES.TERRAN_PLANET:
		planet_spawner.terran_theme = planet_type_value + 1
	else:
		planet_spawner.gaseous_theme = planet_type_value + 1
	
	planet_spawner.set_grid_position(cell.x, cell.y)
	planet_spawner.use_grid_position = true
	planet_spawner.local_seed_offset = seed_offset
	
	var planet = planet_spawner.spawn_planet()
	
	if not planet:
		planet_spawner.queue_free()
		return null
	
	# Register this entity
	_register_generated_entity(cell, planet_spawner, "planet_spawner")
	
	# Connect to planet spawned signal
	if planet_spawner.has_signal("planet_spawned") and not planet_spawner.is_connected("planet_spawned", _on_planet_spawned):
		planet_spawner.connect("planet_spawned", _on_planet_spawned)
	
	return planet

func _generate_asteroid_field(cell: Vector2i, field_seed: int) -> Node:
	var asteroid_field = _scene_cache["asteroid_field"].instantiate()
	add_child(asteroid_field)
	
	# Set grid position which will handle proper world positioning
	if asteroid_field.has_method("set_grid_position"):
		asteroid_field.set_grid_position(cell.x, cell.y)
	else:
		# Fallback to direct position setting
		var world_pos = _cell_to_world_position(cell)
		asteroid_field.global_position = world_pos
	
	# Set local seed offset - direct property access
	asteroid_field.local_seed_offset = field_seed % 1000
	
	# Create deterministic parameters based on field_seed
	var density_seed = field_seed
	var size_seed = field_seed + 1
	var radius_seed = field_seed + 2
	
	var density = 1.0
	var size_variation = 1.0
	var field_radius = 400.0
	
	# Use seed manager for deterministic randomization if available
	if seed_manager:
		density = seed_manager.get_random_value(density_seed, 0.5, 1.5)
		size_variation = seed_manager.get_random_value(size_seed, 0.7, 1.3)
		field_radius = seed_manager.get_random_value(radius_seed, 350.0, 450.0)
	else:
		var rng = RandomNumberGenerator.new()
		rng.seed = field_seed
		density = rng.randf_range(0.5, 1.5)
		size_variation = rng.randf_range(0.7, 1.3)
		field_radius = rng.randf_range(350.0, 450.0)
	
	# Configure field properties - direct access
	asteroid_field.field_radius = field_radius
	
	# Adjust asteroid count based on density - direct access
	asteroid_field.min_asteroids = int(12 * density)  # Default is 12
	asteroid_field.max_asteroids = int(20 * density)  # Default is 20
	
	# Apply size variation setting
	asteroid_field.size_variation = size_variation * 0.4
	
	# Generate the field
	if asteroid_field.has_method("generate_field"):
		asteroid_field.generate_field()
	
	# Register with entity manager
	_register_generated_entity(cell, asteroid_field, "asteroid_field")
	
	if has_node("/root/EntityManager") and EntityManager.has_method("register_entity"):
		EntityManager.register_entity(asteroid_field, "asteroid_field")
	
	return asteroid_field

func _generate_station(cell: Vector2i, station_seed: int) -> Node:
	var station = _scene_cache["station"].instantiate()
	add_child(station)
	
	var world_pos = _cell_to_world_position(cell)
	
	# Add a deterministic offset using consistent seeds
	var offset = Vector2.ZERO
	var cell_size = game_settings.grid_cell_size if game_settings else 1024
	
	var offset_x_seed = station_seed
	var offset_y_seed = station_seed + 1
	
	if seed_manager:
		offset = Vector2(
			seed_manager.get_random_value(offset_x_seed, -cell_size/4.0, cell_size/4.0),
			seed_manager.get_random_value(offset_y_seed, -cell_size/4.0, cell_size/4.0)
		)
	else:
		var rng = RandomNumberGenerator.new()
		rng.seed = station_seed
		offset = Vector2(
			rng.randf_range(-cell_size/4.0, cell_size/4.0),
			rng.randf_range(-cell_size/4.0, cell_size/4.0)
		)
		
	station.global_position = world_pos + offset
	
	if station.has_method("initialize"):
		station.initialize(station_seed)
	
	_register_generated_entity(cell, station, "station")
	
	if has_node("/root/EntityManager") and EntityManager.has_method("register_entity"):
		EntityManager.register_entity(station, "station")
	
	return station

func _on_planet_spawned(planet_instance) -> void:
	if has_node("/root/EntityManager") and EntityManager.has_method("register_entity"):
		EntityManager.register_entity(planet_instance, "planet")

func _generate_entity_seed(cell: Vector2i, entity_type: String, subtype_index: int = 0) -> int:
	var base_seed
	
	if game_settings:
		base_seed = game_settings.get_seed()
	elif seed_manager:
		base_seed = seed_manager.get_seed()
	else:
		base_seed = 12345 # Default deterministic seed
	
	var type_offset
	match entity_type:
		ENTITY_TYPES.TERRAN_PLANET: type_offset = PLANET_SEED_OFFSET + TERRAN_TYPE_OFFSET
		ENTITY_TYPES.GASEOUS_PLANET: type_offset = PLANET_SEED_OFFSET + GASEOUS_TYPE_OFFSET
		ENTITY_TYPES.ASTEROID_FIELD: type_offset = ASTEROID_SEED_OFFSET
		ENTITY_TYPES.STATION: type_offset = STATION_SEED_OFFSET
		_: type_offset = 0
	
	return base_seed + type_offset + (cell.x * 1000) + (cell.y * 100) + subtype_index * 10

# Deterministic shuffling using fixed algorithm
func _shuffle_candidates_deterministic(candidate_cells: Array) -> void:
	if seed_manager:
		# Use a deterministic factor for shuffling
		var shuffle_seed = game_settings.get_seed() * 17 + _generation_id * 31
		seed_manager.shuffle_array(candidate_cells, shuffle_seed)
	else:
		var rng = RandomNumberGenerator.new()
		rng.seed = (game_settings.get_seed() if game_settings else 12345) + _generation_id
		
		# Fisher-Yates shuffle - deterministic order
		for i in range(candidate_cells.size() - 1, 0, -1):
			var j = rng.randi_range(0, i)
			if i != j:
				var temp = candidate_cells[i]
				candidate_cells[i] = candidate_cells[j]
				candidate_cells[j] = temp

func get_candidate_cells() -> Array:
	# Create a fresh copy each time to ensure deterministic order
	var candidates = []
	for cell in _all_candidate_cells:
		if not _excluded_cells.has(cell):
			candidates.append(cell)
	
	return candidates

func mark_proximity_cells(center: Vector2i, proximity: int) -> void:
	if proximity <= 0:
		_excluded_cells[center] = true
		return
	
	# Optimized proximity marking - only process required cells
	for dx in range(-proximity, proximity + 1):
		for dy in range(-proximity, proximity + 1):
			var cell = Vector2i(center.x + dx, center.y + dy)
			if is_valid_cell(cell):
				_excluded_cells[cell] = true

func clear_world() -> void:
	for cell in _generated_entities:
		var cell_data = _generated_entities[cell]
		
		for entity_type in cell_data:
			for entity in cell_data[entity_type]:
				if is_instance_valid(entity):
					if has_node("/root/EntityManager") and EntityManager.has_method("deregister_entity") and entity_type != "planet_spawner":
						EntityManager.deregister_entity(entity)
					
					# Special handling for asteroid fields to ensure proper cleanup
					if entity_type == "asteroid_field" and entity.has_method("clear_field"):
						entity.clear_field()
						
					entity.queue_free()
	
	_generated_entities.clear()
	_excluded_cells.clear()
	_planet_cells.clear()
	
	# Reset entity counts
	for type in ENTITY_TYPES.values():
		_entity_counts[type] = 0

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
		var grid_size = 10    # Default
		var grid_offset = Vector2(cell_size * grid_size / 2, cell_size * grid_size / 2)
		return Vector2(cell.x * cell_size + cell_size/2.0, cell.y * cell_size + cell_size/2.0) - grid_offset

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

func get_entity_at_world_position(world_pos: Vector2, entity_group: String = "") -> Node:
	if not game_settings:
		return null
		
	var cell = game_settings.get_cell_coords(world_pos)
	if not is_valid_cell(cell):
		return null
		
	var entities = get_cell_entities(cell)
	if entities.is_empty():
		return null
		
	# If no group specified, return the first entity
	if entity_group.is_empty():
		return entities[0]
		
	# Otherwise, find entity in the specified group
	for entity in entities:
		if entity.is_in_group(entity_group):
			return entity
			
	return null

func get_nearest_entity_of_type(world_pos: Vector2, entity_type: String) -> Dictionary:
	var nearest_entity = null
	var nearest_distance = INF
	var nearest_cell = Vector2i(-1, -1)
	
	for cell in _generated_entities:
		var cell_data = _generated_entities[cell]
		var cell_has_type = false
		
		for type in cell_data:
			if (type == "planet_spawner" and (entity_type == ENTITY_TYPES.TERRAN_PLANET or entity_type == ENTITY_TYPES.GASEOUS_PLANET)) or \
			   (type == entity_type):
				cell_has_type = true
				break
		
		if not cell_has_type:
			continue
			
		var cell_position = _cell_to_world_position(cell)
		var distance = cell_position.distance_to(world_pos)
		
		if distance < nearest_distance:
			var entities = get_cell_entities(cell)
			if not entities.is_empty():
				nearest_entity = entities[0]
				nearest_distance = distance
				nearest_cell = cell
	
	return {
		"entity": nearest_entity,
		"distance": nearest_distance,
		"cell": nearest_cell
	}

func get_entity_count(entity_type: String) -> int:
	return _entity_counts.get(entity_type, 0)

func get_total_entity_count() -> int:
	var total = 0
	for type in _entity_counts:
		total += _entity_counts[type]
	return total
