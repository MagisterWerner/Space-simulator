# scripts/spawners/spawner_manager.gd
extends Node
class_name SpawnerManager

# Signals
signal spawner_ready(spawner_type)
signal entity_spawned(entity, entity_type, data)

# Spawner instances
var planet_spawner: PlanetSpawner
var asteroid_spawner: AsteroidSpawner
var station_spawner: StationSpawner
var fragment_spawner: FragmentSpawner

# Spawner tracking
var _spawners = {}
var _initialized_spawners = 0
var _total_spawners = 4

# Debug mode
var _debug_mode = false
var _game_settings = null

func _ready() -> void:
	# Find game settings
	_game_settings = get_tree().current_scene.get_node_or_null("GameSettings")
	if _game_settings:
		_debug_mode = _game_settings.debug_mode
	
	# Create and initialize all spawners
	_initialize_spawners()

func _initialize_spawners() -> void:
	# Create spawners
	planet_spawner = PlanetSpawner.new()
	planet_spawner.name = "PlanetSpawner"
	add_child(planet_spawner)
	
	asteroid_spawner = AsteroidSpawner.new()
	asteroid_spawner.name = "AsteroidSpawner"
	add_child(asteroid_spawner)
	
	station_spawner = StationSpawner.new()
	station_spawner.name = "StationSpawner" 
	add_child(station_spawner)
	
	fragment_spawner = FragmentSpawner.new()
	fragment_spawner.name = "FragmentSpawner"
	add_child(fragment_spawner)
	
	# Track spawners
	_spawners["planet"] = planet_spawner
	_spawners["asteroid"] = asteroid_spawner
	_spawners["station"] = station_spawner
	_spawners["fragment"] = fragment_spawner
	
	# Connect signals
	planet_spawner.spawner_ready.connect(_on_spawner_ready.bind("planet"))
	asteroid_spawner.spawner_ready.connect(_on_spawner_ready.bind("asteroid"))
	station_spawner.spawner_ready.connect(_on_spawner_ready.bind("station"))
	fragment_spawner.spawner_ready.connect(_on_spawner_ready.bind("fragment"))
	
	# Connect entity spawned signals
	planet_spawner.entity_spawned.connect(_on_entity_spawned)
	asteroid_spawner.entity_spawned.connect(_on_entity_spawned)
	station_spawner.entity_spawned.connect(_on_entity_spawned)
	fragment_spawner.entity_spawned.connect(_on_entity_spawned)

func _on_spawner_ready(spawner_type: String) -> void:
	_initialized_spawners += 1
	spawner_ready.emit(spawner_type)
	
	if _debug_mode:
		print("SpawnerManager: " + spawner_type + " spawner ready")
	
	# Check if all spawners are ready
	if _initialized_spawners >= _total_spawners:
		if _debug_mode:
			print("SpawnerManager: All spawners ready")

func _on_entity_spawned(entity: Node, data) -> void:
	# Determine entity type from data
	var entity_type = "unknown"
	
	if data is PlanetData:
		entity_type = "planet"
	elif data is MoonData:
		entity_type = "moon"
	elif data is AsteroidData:
		entity_type = "asteroid"
	elif data is AsteroidFieldData:
		entity_type = "asteroid_field"
	elif data is StationData:
		entity_type = "station"
	
	# Emit our own signal
	entity_spawned.emit(entity, entity_type, data)

# Main methods for spawning entities

# Spawn any entity from data
func spawn_entity(data: EntityData) -> Node:
	await _ensure_spawners_ready()
	
	if data is PlanetData:
		return planet_spawner.spawn_entity(data)
	elif data is MoonData:
		return planet_spawner.spawn_entity(data)
	elif data is AsteroidData:
		return asteroid_spawner.spawn_entity(data)
	elif data is AsteroidFieldData:
		return asteroid_spawner.spawn_entity(data)
	elif data is StationData:
		return station_spawner.spawn_entity(data)
	else:
		push_error("SpawnerManager: Unknown data type: " + str(data.get_class()))
		return null

# Spawn a planet at a specific grid cell
func spawn_planet_at_cell(cell: Vector2i, is_gaseous: bool = false, theme_id: int = -1) -> Node:
	await _ensure_spawners_ready()
	return planet_spawner.spawn_planet_at_cell(cell, is_gaseous, theme_id)

# Spawn an asteroid field at a specific grid cell
func spawn_asteroid_field_at_cell(cell: Vector2i) -> Node:
	await _ensure_spawners_ready()
	return asteroid_spawner.spawn_asteroid_field_at_cell(cell)

# Spawn a station at a specific grid cell
func spawn_station_at_cell(cell: Vector2i, station_type: int = StationData.StationType.TRADING) -> Node:
	await _ensure_spawners_ready()
	return station_spawner.spawn_station_at_cell(cell, station_type)

# Spawn asteroid fragments
func spawn_fragments(asteroid_node: Node, asteroid_data: AsteroidData) -> Array:
	await _ensure_spawners_ready()
	return fragment_spawner.spawn_fragments(asteroid_node, asteroid_data)

# Spawn fragments at a specific position
func spawn_fragments_at(position: Vector2, size_category: String, parent_velocity: Vector2 = Vector2.ZERO) -> Array:
	await _ensure_spawners_ready()
	return fragment_spawner.spawn_fragments_at(position, size_category, parent_velocity)

# Clear all spawned entities
func clear_all_entities() -> void:
	await _ensure_spawners_ready()
	
	planet_spawner.clear_spawned_entities()
	asteroid_spawner.clear_spawned_entities()
	station_spawner.clear_spawned_entities()
	fragment_spawner.clear_spawned_entities()

# Helper to ensure all spawners are ready
func _ensure_spawners_ready() -> void:
	# Check if all spawners are already initialized
	if _initialized_spawners >= _total_spawners:
		return
	
	# Wait for each spawner individually
	if not planet_spawner._initialized:
		await planet_spawner.spawner_ready
	
	if not asteroid_spawner._initialized:
		await asteroid_spawner.spawner_ready
	
	if not station_spawner._initialized:
		await station_spawner.spawner_ready
	
	if not fragment_spawner._initialized:
		await fragment_spawner.spawner_ready
