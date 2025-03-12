extends Node
class_name WorldGenerator

signal world_generation_started
signal world_generation_completed
signal entity_generated(entity, type, cell)
signal planet_generation_progress(completed, total)

var game_settings: GameSettings = null
var seed_manager = null

# Modified to use async planet spawners
var async_planet_spawner_scene: PackedScene
var asteroid_field_scene: PackedScene
var station_scene: PackedScene

var _generated_cells := {}
var _entity_counts := {
	"terran_planet": 0,
	"gaseous_planet": 0,
	"asteroid_field": 0,
	"station": 0
}
var _planet_spawners := {}
var _planet_cells: Array[Vector2i] = []
var _proximity_excluded_cells := {}
var debug_mode := false

# Async generation tracking
var _pending_generations := 0
var _completed_generations := 0
var _total_planets_to_generate := 0
var _generation_in_progress := false

const PLANET_SEED_OFFSET := 1000000
const ASTEROID_SEED_OFFSET := 2000000
const STATION_SEED_OFFSET := 3000000
const TERRAN_TYPE_OFFSET := 10000
const GASEOUS_TYPE_OFFSET := 20000

func _ready() -> void:
	var main_scene = get_tree().current_scene
	game_settings = main_scene.get_node_or_null("GameSettings")
	
	if game_settings:
		if not game_settings.is_connected("debug_settings_changed", _on_debug_settings_changed):
			game_settings.connect("debug_settings_changed", _on_debug_settings_changed)
		debug_mode = game_settings.debug_mode and game_settings.debug_world_generator
	
	if Engine.has_singleton("SeedManager"):
		seed_manager = Engine.get_singleton("SeedManager")
		if not seed_manager.is_initialized and seed_manager.has_signal("seed_initialized"):
			await seed_manager.seed_initialized
	
	_initialize_scenes()
	_debug("Initialized with game seed " + str(game_settings.get_seed() if game_settings else "N/A"))

func _on_debug_settings_changed(debug_settings: Dictionary) -> void:
	debug_mode = debug_settings.get("master", false) and debug_settings.get("world_generator", false)
	
	if debug_mode:
		_debug("Debug mode enabled, current entities: " + str(_entity_counts))

func _debug(message: String) -> void:
	if not debug_mode:
		return
		
	if Engine.has_singleton("DebugLogger"):
		DebugLogger.debug("WorldGenerator", message)
	else:
		print("WorldGenerator: " + message)

func _initialize_scenes() -> void:
	# Load the async planet spawner
	if ResourceLoader.exists("res://scenes/spawners/async_planet_spawner.tscn"):
		async_planet_spawner_scene = load("res://scenes/spawners/async_planet_spawner.tscn")
	else:
		# Create a scene from the script if the scene doesn't exist
		var script = load("res://scripts/spawners/async_planet.spawner.gd")
		if script:
			async_planet_spawner_scene = PackedScene.new()
			var planet_node = Node2D.new()
			planet_node.set_script(script)
			var result = async_planet_spawner_scene.pack(planet_node)
			if result != OK:
				push_error("WorldGenerator: Failed to create async planet spawner scene")
	
	# Load other scenes
	if ResourceLoader.exists("res://scenes/world/asteroid_field.tscn"):
		asteroid_field_scene = load("res://scenes/world/asteroid_field.tscn")
		
	if ResourceLoader.exists("res://scenes/world/station.tscn"):
		station_scene = load("res://scenes/world/station.tscn")

func generate_starter_world() -> Dictionary:
	clear_world()
	world_generation_started.emit()
	
	_planet_cells.clear()
	_proximity_excluded_cells.clear()
	_planet_spawners.clear()
	_pending_generations = 0
	_completed_generations = 0
	_generation_in_progress = true
	
	# Count total planets to generate for progress tracking
	var total_terran_planets = game_settings.terran_planets if game_settings else 5
	var total_gaseous_planets = game_settings.gaseous_planets if game_settings else 1
	_total_planets_to_generate = total_terran_planets + total_gaseous_planets
	
	# Generate player's starting planet first
	var player_planet_cell = generate_planet("terran_planet", 1, true)
	
	var gaseous_planet_cell = Vector2i(-1, -1)
	
	# Generate gaseous planets
	if total_gaseous_planets > 0:
		gaseous_planet_cell = generate_planet("gaseous_planet", 2)
		
		for i in range(1, total_gaseous_planets):
			generate_planet("gaseous_planet", 2)
	
	# Generate remaining terran planets
	var max_planets = calculate_max_planets()
	
	for i in range(1, total_terran_planets):
		if _entity_counts.terran_planet + _entity_counts.gaseous_planet < max_planets:
			generate_planet("terran_planet", 1)
		else:
			_debug("Maximum planet limit reached, stopping planet generation.")
			break
	
	# Generate asteroid fields
	var asteroid_count = game_settings.asteroid_fields if game_settings else 0
	for i in range(asteroid_count):
		generate_asteroid_field()
	
	# Generate stations
	var station_count = game_settings.space_stations if game_settings else 0
	for i in range(station_count):
		generate_station()
	
	# If no pending generations, emit completion signal immediately
	if _pending_generations == 0:
		_complete_generation()
	
	_debug("Starter world generation initiated")
	_debug("- Player planet cell: " + str(player_planet_cell))
	_debug("- Expected total terran planets: " + str(total_terran_planets))
	_debug("- Expected total gaseous planets: " + str(total_gaseous_planets))
	
	return {
		"player_planet_cell": player_planet_cell,
		"gaseous_planet_cell": gaseous_planet_cell
	}

func _complete_generation() -> void:
	_generation_in_progress = false
	world_generation_completed.emit()
	
	_debug("World generation complete")
	_debug("- Total terran planets: " + str(_entity_counts.terran_planet))
	_debug("- Total gaseous planets: " + str(_entity_counts.gaseous_planet))
	_debug("- Total asteroid fields: " + str(_entity_counts.asteroid_field))
	_debug("- Total stations: " + str(_entity_counts.station))

func calculate_max_planets() -> int:
	var total_cells = game_settings.grid_size * game_settings.grid_size if game_settings else 25
	return _entity_counts.terran_planet + _entity_counts.gaseous_planet + (total_cells - _proximity_excluded_cells.size())

func _generate_entity_seed(cell: Vector2i, entity_type: String, subtype_index: int = 0) -> int:
	var base_seed := 0
	if game_settings:
		base_seed = game_settings.get_seed()
	elif seed_manager:
		base_seed = seed_manager.get_seed()
	else:
		base_seed = get_instance_id()
	
	var type_offset := 0
	match entity_type:
		"terran_planet":
			type_offset = PLANET_SEED_OFFSET + TERRAN_TYPE_OFFSET
		"gaseous_planet":
			type_offset = PLANET_SEED_OFFSET + GASEOUS_TYPE_OFFSET
		"asteroid_field":
			type_offset = ASTEROID_SEED_OFFSET
		"station":
			type_offset = STATION_SEED_OFFSET
	
	var cell_offset := (cell.x * 1000) + (cell.y * 100)
	var subtype_offset := subtype_index * 10
	
	return base_seed + type_offset + cell_offset + subtype_offset

func _shuffle_candidates(candidate_cells: Array) -> void:
	if seed_manager:
		seed_manager.shuffle_array(candidate_cells, get_instance_id())
	else:
		var seed_value = game_settings.get_seed() if game_settings else get_instance_id()
		var temp_rng = RandomNumberGenerator.new()
		temp_rng.seed = seed_value
		
		for i in range(candidate_cells.size() - 1, 0, -1):
			var j = temp_rng.randi_range(0, i)
			var temp = candidate_cells[i]
			candidate_cells[i] = candidate_cells[j]
			candidate_cells[j] = temp

func get_candidate_cells() -> Array:
	var candidate_cells = []
	var grid_size = game_settings.grid_size if game_settings else 5
	
	for x in range(grid_size):
		for y in range(grid_size):
			var cell = Vector2i(x, y)
			if not _proximity_excluded_cells.has(cell):
				candidate_cells.append(cell)
	
	return candidate_cells

# Modified to use async planet spawners
func generate_planet(planet_type: String, proximity: int = 1, is_player_starting: bool = false) -> Vector2i:
	if async_planet_spawner_scene == null:
		push_error("WorldGenerator: Async planet spawner scene not loaded")
		return Vector2i(-1, -1)
	
	var candidate_cells = get_candidate_cells()
	_shuffle_candidates(candidate_cells)
	
	for cell in candidate_cells:
		if is_cell_generated(cell):
			continue
		
		var cell_seed = _generate_entity_seed(cell, planet_type)
		
		# Create async planet spawner
		var planet_spawner = async_planet_spawner_scene.instantiate()
		add_child(planet_spawner)
		
		# Calculate world position
		var world_pos
		if game_settings:
			world_pos = game_settings.get_cell_world_position(cell)
		else:
			world_pos = Vector2(cell.x * 1024, cell.y * 1024)
		
		planet_spawner.global_position = world_pos
		
		# Set up planet type
		var is_gaseous = (planet_type == "gaseous_planet")
		planet_spawner.is_gaseous = is_gaseous
		
		# Determine theme
		var theme_value: int
		if planet_type == "terran_planet" and is_player_starting and game_settings:
			theme_value = game_settings.player_starting_planet_type
		else:
			if seed_manager:
				theme_value = seed_manager.get_random_int(cell_seed, 0, 6 if planet_type == "terran_planet" else 3)
			else:
				var temp_rng = RandomNumberGenerator.new()
				temp_rng.seed = cell_seed
				theme_value = temp_rng.randi_range(0, 6 if planet_type == "terran_planet" else 3)
				
			if planet_type == "terran_planet" and game_settings and theme_value == game_settings.player_starting_planet_type:
				theme_value = (theme_value + 1) % 7
		
		# Set theme override
		planet_spawner.theme_override = theme_value
		
		# Connect signals
		if planet_spawner.has_signal("planet_ready"):
			planet_spawner.planet_ready.connect(_on_planet_ready.bind(planet_spawner, planet_type, cell))
		
		if planet_spawner.has_signal("generation_started"):
			planet_spawner.generation_started.connect(_on_planet_generation_started.bind(planet_spawner, cell))
			
		if planet_spawner.has_signal("generation_failed"):
			planet_spawner.generation_failed.connect(_on_planet_generation_failed.bind(planet_spawner, cell))
		
		# Start generation with the determined seed
		planet_spawner.generate_planet(cell_seed)
		
		# Track generation
		_pending_generations += 1
		
		if not _generated_cells.has(cell):
			_generated_cells[cell] = {
				"planets": [],
				"asteroid_fields": [],
				"stations": []
			}
		
		_planet_spawners[cell] = planet_spawner
		_generated_cells[cell].planets.append(planet_spawner)
		
		# We count the planet now, even though it's not fully generated yet
		_entity_counts[planet_type] += 1
		
		mark_proximity_cells(cell, proximity)
		_planet_cells.append(cell)
		
		_debug("Started generating " + planet_type + " at cell " + str(cell))
		if planet_type == "terran_planet" and is_player_starting:
			_debug("This is the player's starting planet (theme: " + 
				game_settings.get_planet_type_name(theme_value) + ")")
		
		return cell
	
	push_warning("WorldGenerator: Failed to generate " + planet_type + " - no valid cells available")
	return Vector2i(-1, -1)

# Signal handlers for async planet generation
func _on_planet_generation_started(spawner, cell) -> void:
	_debug("Planet generation started at cell " + str(cell))

func _on_planet_ready(spawner, planet_type, cell) -> void:
	_debug("Planet generation completed at cell " + str(cell))
	
	# Get the planet instance from the spawner
	var planet = null
	if spawner.has_method("get_planet_sprite"):
		planet = spawner.get_planet_sprite()
	else:
		planet = spawner # Use spawner as fallback
	
	# Register with EntityManager if available
	if has_node("/root/EntityManager") and EntityManager.has_method("register_entity"):
		EntityManager.register_entity(planet, "planet")
	
	entity_generated.emit(planet, planet_type, cell)
	
	# Update generation tracking
	_completed_generations += 1
	_pending_generations -= 1
	
	# Emit progress signal
	planet_generation_progress.emit(_completed_generations, _total_planets_to_generate)
	
	# Check if all generations are complete
	if _generation_in_progress and _pending_generations <= 0:
		_complete_generation()

func _on_planet_generation_failed(error, spawner, cell) -> void:
	_debug("Planet generation failed at cell " + str(cell) + ": " + str(error))
	
	# Update generation tracking
	_pending_generations -= 1
	
	# Remove the spawner from the cell
	if _generated_cells.has(cell):
		var planets = _generated_cells[cell].planets
		var index = planets.find(spawner)
		if index >= 0:
			planets.remove_at(index)
	
	# Clean up spawner
	if is_instance_valid(spawner):
		spawner.queue_free()
	
	# Check if all generations are complete
	if _generation_in_progress and _pending_generations <= 0:
		_complete_generation()

func generate_asteroid_field() -> Vector2i:
	if asteroid_field_scene == null:
		push_error("WorldGenerator: asteroid_field_scene not loaded")
		return Vector2i(-1, -1)
	
	var candidate_cells = get_candidate_cells()
	_shuffle_candidates(candidate_cells)
	
	for cell in candidate_cells:
		if is_cell_generated(cell):
			continue
			
		var field_seed = _generate_entity_seed(cell, "asteroid_field")
		
		var asteroid_field = asteroid_field_scene.instantiate()
		add_child(asteroid_field)
		
		var world_pos
		if game_settings:
			world_pos = game_settings.get_cell_world_position(cell)
		else:
			world_pos = Vector2(cell.x * 1024, cell.y * 1024)
			
		asteroid_field.global_position = world_pos
		
		if asteroid_field.has_method("generate"):
			var density = 1.0
			var size = 1.0
			
			if seed_manager:
				density = seed_manager.get_random_value(field_seed, 0.5, 1.5)
				size = seed_manager.get_random_value(field_seed + 1, 0.7, 1.3)
			else:
				var temp_rng = RandomNumberGenerator.new()
				temp_rng.seed = field_seed
				density = temp_rng.randf_range(0.5, 1.5)
				size = temp_rng.randf_range(0.7, 1.3)
			
			asteroid_field.generate(field_seed, density, size)
		
		if not _generated_cells.has(cell):
			_generated_cells[cell] = {
				"planets": [],
				"asteroid_fields": [],
				"stations": []
			}
			
		_generated_cells[cell].asteroid_fields.append(asteroid_field)
		_entity_counts.asteroid_field += 1
		
		if has_node("/root/EntityManager") and EntityManager.has_method("register_entity"):
			EntityManager.register_entity(asteroid_field, "asteroid_field")
		
		entity_generated.emit(asteroid_field, "asteroid_field", cell)
		_debug("Generated asteroid field at cell " + str(cell))
		
		return cell
	
	push_warning("WorldGenerator: Failed to generate asteroid field - no valid cells available")
	return Vector2i(-1, -1)

func generate_station() -> Vector2i:
	if station_scene == null:
		push_error("WorldGenerator: station_scene not loaded")
		return Vector2i(-1, -1)
	
	var candidate_cells = get_candidate_cells()
	_shuffle_candidates(candidate_cells)
	
	for cell in candidate_cells:
		if is_cell_generated(cell):
			continue
			
		var station_seed = _generate_entity_seed(cell, "station")
		
		var station = station_scene.instantiate()
		add_child(station)
		
		var world_pos
		if game_settings:
			world_pos = game_settings.get_cell_world_position(cell)
		else:
			world_pos = Vector2(cell.x * 1024, cell.y * 1024)
			
		station.global_position = world_pos
		
		var cell_size = game_settings.grid_cell_size if game_settings else 1024
		var offset = Vector2.ZERO
		
		if seed_manager:
			offset = Vector2(
				seed_manager.get_random_value(station_seed, -cell_size/4.0, cell_size/4.0),
				seed_manager.get_random_value(station_seed + 1, -cell_size/4.0, cell_size/4.0)
			)
		else:
			var temp_rng = RandomNumberGenerator.new()
			temp_rng.seed = station_seed
			offset = Vector2(
				temp_rng.randf_range(-cell_size/4.0, cell_size/4.0),
				temp_rng.randf_range(-cell_size/4.0, cell_size/4.0)
			)
			
		station.global_position += offset
		
		if station.has_method("initialize"):
			station.initialize(station_seed)
		
		if not _generated_cells.has(cell):
			_generated_cells[cell] = {
				"planets": [],
				"asteroid_fields": [],
				"stations": []
			}
			
		_generated_cells[cell].stations.append(station)
		_entity_counts.station += 1
		
		if has_node("/root/EntityManager") and EntityManager.has_method("register_entity"):
			EntityManager.register_entity(station, "station")
		
		entity_generated.emit(station, "station", cell)
		_debug("Generated station at cell " + str(cell))
		
		return cell
	
	push_warning("WorldGenerator: Failed to generate station - no valid cells available")
	return Vector2i(-1, -1)

func mark_proximity_cells(center: Vector2i, proximity: int) -> void:
	if proximity <= 0:
		_proximity_excluded_cells[center] = true
		return
	
	for dx in range(-proximity, proximity + 1):
		for dy in range(-proximity, proximity + 1):
			var cell = Vector2i(center.x + dx, center.y + dy)
			if is_valid_cell(cell):
				_proximity_excluded_cells[cell] = true

func clear_world() -> void:
	for cell in _generated_cells:
		var cell_data = _generated_cells[cell]
		
		for planet_spawner in cell_data.planets:
			if is_instance_valid(planet_spawner):
				# Cancel any pending generations
				if planet_spawner.has_method("cancel_generation"):
					planet_spawner.cancel_generation()
				planet_spawner.queue_free()
		
		for asteroid_field in cell_data.asteroid_fields:
			if is_instance_valid(asteroid_field):
				asteroid_field.queue_free()
		
		for station in cell_data.stations:
			if is_instance_valid(station):
				if has_node("/root/EntityManager") and EntityManager.has_method("deregister_entity"):
					EntityManager.deregister_entity(station)
				station.queue_free()
	
	_generated_cells.clear()
	_entity_counts = {
		"terran_planet": 0,
		"gaseous_planet": 0,
		"asteroid_field": 0,
		"station": 0
	}
	
	_planet_cells.clear()
	_proximity_excluded_cells.clear()
	_planet_spawners.clear()
	_pending_generations = 0
	_completed_generations = 0
	
	_debug("World cleared")

func is_valid_cell(cell_coords: Vector2i) -> bool:
	var grid_size = game_settings.grid_size if game_settings else 5
	return (
		cell_coords.x >= 0 and cell_coords.x < grid_size and
		cell_coords.y >= 0 and cell_coords.y < grid_size
	)

func is_cell_generated(cell_coords: Vector2i) -> bool:
	return _generated_cells.has(cell_coords) and (
		not _generated_cells[cell_coords].planets.is_empty() or
		not _generated_cells[cell_coords].asteroid_fields.is_empty() or
		not _generated_cells[cell_coords].stations.is_empty()
	)

func get_cell_entities(cell_coords: Vector2i) -> Array:
	if not _generated_cells.has(cell_coords):
		return []
		
	var result = []
	var cell_data = _generated_cells[cell_coords]
	
	# Get planets from the async spawners
	for planet_spawner in cell_data.planets:
		if is_instance_valid(planet_spawner):
			# For async spawners, use the sprite or the spawner itself
			if planet_spawner.has_method("get_planet_sprite") and planet_spawner.is_planet_ready:
				var planet = planet_spawner.get_planet_sprite()
				if planet:
					result.append(planet)
			else:
				result.append(planet_spawner)
	
	for asteroid_field in cell_data.asteroid_fields:
		if is_instance_valid(asteroid_field):
			result.append(asteroid_field)
	
	for station in cell_data.stations:
		if is_instance_valid(station):
			result.append(station)
	
	return result

# Get generation status
func get_generation_progress() -> Dictionary:
	return {
		"completed": _completed_generations,
		"total": _total_planets_to_generate,
		"pending": _pending_generations,
		"in_progress": _generation_in_progress
	}

# Check if all world generation is complete
func is_generation_complete() -> bool:
	return not _generation_in_progress
