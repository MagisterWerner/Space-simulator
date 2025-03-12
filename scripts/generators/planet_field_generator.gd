extends Node2D
class_name PlanetFieldGenerator

# Signals
signal generation_started(total_planets)
signal planet_generated(index, total)
signal generation_completed
signal sector_updated(sector_coords)

# Configuration
@export var grid_cell_size: int = 10000
@export var planets_per_sector: int = 5
@export var min_planet_distance: float = 1000.0
@export var max_generation_per_frame: int = 2
@export var camera_follow_distance: float = 5000.0
@export var planet_scene: PackedScene = null
@export var load_adjacent_sectors: bool = true
@export var unload_distant_sectors: bool = true
@export var max_loaded_sectors: int = 9

# Internal state
var _current_player_sector: Vector2i = Vector2i(-999, -999)
var _last_camera_position: Vector2 = Vector2.ZERO
var _loaded_sectors = {}
var _generating_sectors = {}
var _pending_sector_generations = []
var _planets_array = []
var _generation_paused = false
var _seed = 0

func _ready():
	# Set a default seed
	_seed = SeedManager.get_seed() if has_node("/root/SeedManager") else 12345
	
	# Create default planet scene if none provided
	if planet_scene == null:
		var script = load("res://scripts/spawners/async_planet_spawner.gd")
		if script:
			planet_scene = PackedScene.new()
			var planet_node = Node2D.new()
			planet_node.set_script(script)
			var packed_scene = planet_scene.pack(planet_node)
			if packed_scene != OK:
				push_error("PlanetFieldGenerator: Failed to create default planet scene")
				planet_scene = null

func _process(_delta):
	# Check for player movement to a new sector
	var camera = get_viewport().get_camera_2d()
	if camera == null:
		return
		
	var camera_pos = camera.global_position
	
	# Only update if camera has moved significantly
	if _last_camera_position.distance_to(camera_pos) < camera_follow_distance / 10.0:
		return
		
	_last_camera_position = camera_pos
	
	# Calculate sector coordinates
	var sector_x = int(floor(camera_pos.x / grid_cell_size))
	var sector_y = int(floor(camera_pos.y / grid_cell_size))
	var new_sector = Vector2i(sector_x, sector_y)
	
	# If sector changed, update loaded sectors
	if new_sector != _current_player_sector:
		var old_sector = _current_player_sector
		_current_player_sector = new_sector
		_update_sectors()
		sector_updated.emit(_current_player_sector)

func _update_sectors():
	if _generation_paused:
		return
		
	# Determine which sectors should be loaded
	var sectors_to_load = []
	sectors_to_load.append(_current_player_sector)
	
	if load_adjacent_sectors:
		# Add adjacent sectors
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				
				sectors_to_load.append(_current_player_sector + Vector2i(dx, dy))
	
	# Generate any new sectors needed
	for sector in sectors_to_load:
		if not _loaded_sectors.has(sector) and not _generating_sectors.has(sector):
			# Queue this sector for generation
			_generating_sectors[sector] = true
			_pending_sector_generations.append(sector)
	
	# Process pending generations - limited per frame
	_process_pending_generations(max_generation_per_frame)
	
	# Unload distant sectors if needed
	if unload_distant_sectors:
		_unload_distant_sectors()

func _process_pending_generations(max_count: int):
	var processed = 0
	
	while not _pending_sector_generations.is_empty() and processed < max_count:
		var sector = _pending_sector_generations.pop_front()
		
		# Double-check it's still valid to generate this sector
		if _loaded_sectors.has(sector):
			_generating_sectors.erase(sector)
			continue
		
		# Start generation of this sector
		_generate_sector(sector)
		processed += 1

func _generate_sector(sector: Vector2i):
	# Calculate sector center in world coordinates
	var sector_center = Vector2(
		sector.x * grid_cell_size + grid_cell_size / 2,
		sector.y * grid_cell_size + grid_cell_size / 2
	)
	
	# Create planet array for this sector
	var planets = []
	_loaded_sectors[sector] = planets
	
	# Generate planet positions
	var positions = _generate_planet_positions(sector, planets_per_sector)
	
	# Create planets
	var planet_count = positions.size()
	generation_started.emit(planet_count)
	
	for i in range(planet_count):
		var position = positions[i]
		var planet = _create_planet(sector, i, position)
		if planet:
			planets.append(planet)
			planet_generated.emit(i, planet_count)
	
	# Mark sector as no longer generating
	_generating_sectors.erase(sector)
	
	if planet_count > 0:
		generation_completed.emit()

func _generate_planet_positions(sector: Vector2i, count: int) -> Array:
	var positions = []
	var sector_seed = hash(str(_seed) + str(sector.x) + "," + str(sector.y))
	var rng = RandomNumberGenerator.new()
	rng.seed = sector_seed
	
	# Track used positions to prevent overlap
	var used_positions = []
	var attempts = 0
	var max_attempts = count * 10
	
	while positions.size() < count and attempts < max_attempts:
		attempts += 1
		
		# Generate random position within sector
		var pos_x = rng.randf_range(0, grid_cell_size) + sector.x * grid_cell_size
		var pos_y = rng.randf_range(0, grid_cell_size) + sector.y * grid_cell_size
		var new_pos = Vector2(pos_x, pos_y)
		
		# Check if too close to other planets
		var too_close = false
		for existing_pos in used_positions:
			if existing_pos.distance_to(new_pos) < min_planet_distance:
				too_close = true
				break
		
		if not too_close:
			positions.append(new_pos)
			used_positions.append(new_pos)
	
	return positions

func _create_planet(sector: Vector2i, index: int, position: Vector2):
	if planet_scene == null:
		return null
	
	# Instantiate planet
	var planet = planet_scene.instantiate()
	if not planet:
		return null
		
	add_child(planet)
	planet.global_position = position
	
	# Set deterministic seed for planet generation
	var planet_seed
	if has_node("/root/SeedManager") and SeedManager.is_initialized:
		# Get reproducible seed based on sector and index
		var object_id = hash(str(_seed) + str(sector.x) + "," + str(sector.y) + "_" + str(index))
		planet_seed = SeedManager.get_random_int(object_id, 0, 9999999)
	else:
		# Fallback to manual hashing
		var hash_base = hash(str(_seed) + str(sector.x) + "," + str(sector.y) + "_" + str(index))
		var rng = RandomNumberGenerator.new()
		rng.seed = hash_base
		planet_seed = rng.randi()
	
	# Determine if gaseous (larger planets are more likely to be gas giants)
	var is_gaseous = false
	if has_node("/root/SeedManager") and SeedManager.is_initialized:
		is_gaseous = SeedManager.get_random_bool(planet_seed, 0.3)  # 30% chance
	else:
		var rng = RandomNumberGenerator.new()
		rng.seed = planet_seed
		is_gaseous = rng.randf() < 0.3  # 30% chance
	
	# Prioritize planets closer to the player
	var priority = GenerationManager.Priority.NORMAL
	var distance_to_player = position.distance_to(_last_camera_position)
	if distance_to_player < camera_follow_distance:
		priority = GenerationManager.Priority.HIGH
	elif distance_to_player > camera_follow_distance * 3:
		priority = GenerationManager.Priority.LOW
	
	# Start async generation
	if planet.has_method("generate_planet"):
		planet.generate_planet(planet_seed)
	
	return planet

func _unload_distant_sectors():
	# Don't unload if we're under the limit
	if _loaded_sectors.size() <= max_loaded_sectors:
		return
	
	# Calculate distances to loaded sectors
	var sector_distances = []
	for sector in _loaded_sectors:
		var distance = _calculate_sector_distance(_current_player_sector, sector)
		sector_distances.append({
			"sector": sector,
			"distance": distance
		})
	
	# Sort by distance (farthest first)
	sector_distances.sort_custom(Callable(self, "_sort_sectors_by_distance"))
	
	# Remove excess sectors
	var sectors_to_remove = sector_distances.size() - max_loaded_sectors
	for i in range(sectors_to_remove):
		var sector = sector_distances[i].sector
		_unload_sector(sector)

func _sort_sectors_by_distance(a, b):
	return a.distance > b.distance  # Descending order (farthest first)

func _calculate_sector_distance(sector_a: Vector2i, sector_b: Vector2i) -> float:
	var dx = sector_a.x - sector_b.x
	var dy = sector_a.y - sector_b.y
	return sqrt(dx * dx + dy * dy)

func _unload_sector(sector: Vector2i):
	if not _loaded_sectors.has(sector):
		return
	
	# Get planets in this sector
	var planets = _loaded_sectors[sector]
	
	# Remove planets
	for planet in planets:
		if is_instance_valid(planet):
			# Cancel any pending generations
			if planet.has_method("cancel_generation"):
				planet.cancel_generation()
			planet.queue_free()
	
	# Remove from loaded sectors
	_loaded_sectors.erase(sector)

# Public methods

# Set the seed for planet generation
func set_seed(new_seed: int):
	_seed = new_seed
	
	# Regenerate all sectors with new seed
	regenerate_all()

# Force regeneration of all loaded sectors
func regenerate_all():
	# Store current sectors
	var current_sectors = _loaded_sectors.keys()
	
	# Clear all sectors
	for sector in current_sectors:
		_unload_sector(sector)
	
	# Clear pending generations
	_pending_sector_generations.clear()
	_generating_sectors.clear()
	
	# Trigger update
	_update_sectors()

# Pause/resume generation
func set_paused(paused: bool):
	_generation_paused = paused

# Force generation of a specific sector
func generate_specific_sector(sector: Vector2i):
	if _loaded_sectors.has(sector) or _generating_sectors.has(sector):
		return
	
	_generating_sectors[sector] = true
	_pending_sector_generations.append(sector)
	_process_pending_generations(1)  # Process immediately

# Get current player sector
func get_current_sector() -> Vector2i:
	return _current_player_sector

# Get loaded sectors
func get_loaded_sectors() -> Array:
	return _loaded_sectors.keys()

# Get pending sectors
func get_pending_sectors() -> Array:
	return _pending_sector_generations

# Get sector world coordinates (center)
func get_sector_center(sector: Vector2i) -> Vector2:
	return Vector2(
		sector.x * grid_cell_size + grid_cell_size / 2,
		sector.y * grid_cell_size + grid_cell_size / 2
	)
