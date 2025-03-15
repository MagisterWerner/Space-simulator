extends Node
class_name SpawnerManager

# Signals
signal spawner_ready(spawner_type)
signal entity_spawned(entity, entity_type, data)

# Spawner instances
var planet_spawner: PlanetSpawner
var asteroid_spawner: AsteroidSpawner
var fragment_spawner: FragmentSpawner

# Generator references for data generation
var planet_generator = null
var asteroid_generator = null

# Spawner tracking
var _spawners = {}
var _initialized_spawners = 0
var _total_spawners = 3  # Reduced from 4 to 3 (removed station spawner)

# Debug mode
var _debug_mode = false
var _game_settings = null

func _ready() -> void:
	# Add to spawner_managers group
	add_to_group("spawner_managers")
	
	# Find game settings
	_game_settings = get_tree().current_scene.get_node_or_null("GameSettings")
	if _game_settings:
		_debug_mode = _game_settings.debug_mode
	
	# Create generators first
	_create_generators()
	
	# Create and initialize all spawners
	_initialize_spawners()

func _create_generators() -> void:
	# Create data generators for use by this manager
	planet_generator = PlanetDataGenerator.new()
	add_child(planet_generator)
	
	asteroid_generator = AsteroidDataGenerator.new()
	add_child(asteroid_generator)

func _initialize_spawners() -> void:
	# Create spawners
	planet_spawner = PlanetSpawner.new()
	planet_spawner.name = "PlanetSpawner"
	add_child(planet_spawner)
	
	asteroid_spawner = AsteroidSpawner.new()
	asteroid_spawner.name = "AsteroidSpawner"
	add_child(asteroid_spawner)
	
	fragment_spawner = FragmentSpawner.new()
	fragment_spawner.name = "FragmentSpawner"
	add_child(fragment_spawner)
	
	# Track spawners
	_spawners["planet"] = planet_spawner
	_spawners["asteroid"] = asteroid_spawner
	_spawners["fragment"] = fragment_spawner
	
	# Connect signals
	planet_spawner.spawner_ready.connect(_on_spawner_ready.bind("planet"))
	asteroid_spawner.spawner_ready.connect(_on_spawner_ready.bind("asteroid"))
	fragment_spawner.spawner_ready.connect(_on_spawner_ready.bind("fragment"))
	
	# Connect entity spawned signals
	planet_spawner.entity_spawned.connect(_on_entity_spawned)
	asteroid_spawner.entity_spawned.connect(_on_entity_spawned)
	fragment_spawner.entity_spawned.connect(_on_entity_spawned)

	# Connect to asteroid_destroyed events
	if has_node("/root/EventManager"):
		var event_manager = get_node("/root/EventManager")
		if not event_manager.is_connected("asteroid_destroyed", _on_asteroid_destroyed):
			# Use safe_connect which adds the signal if it doesn't exist
			event_manager.safe_connect("asteroid_destroyed", _on_asteroid_destroyed)

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
	
	# Emit our own signal
	entity_spawned.emit(entity, entity_type, data)

func _on_asteroid_destroyed(position: Vector2, size: String) -> void:
	# Handle asteroid destruction by spawning fragments
	spawn_fragments_at(position, size)

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
	else:
		push_error("SpawnerManager: Unknown data type: " + str(data.get_class()))
		return null

# Generate and spawn a planet at a specific grid cell
func spawn_planet_at_cell(cell: Vector2i, is_gaseous: bool = false, theme_id: int = -1) -> Node:
	await _ensure_spawners_ready()
	
	# Generate planet data
	var planet_data = _generate_planet_at_cell(cell, is_gaseous, theme_id)
	
	# Spawn using the generated data
	return planet_spawner.spawn_entity(planet_data)

# Generate and spawn an asteroid field at a specific grid cell
func spawn_asteroid_field_at_cell(cell: Vector2i) -> Node:
	await _ensure_spawners_ready()
	
	# Generate asteroid field data
	var field_data = _generate_asteroid_field_at_cell(cell)
	
	# Spawn using the generated data
	return asteroid_spawner.spawn_entity(field_data)

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
	fragment_spawner.clear_active_fragments()

# Generate planet data for a cell
func _generate_planet_at_cell(cell: Vector2i, is_gaseous: bool, theme_id: int) -> PlanetData:
	# Get a deterministic entity ID
	var entity_id = _get_deterministic_entity_id(cell)
	
	# Calculate world position from cell
	var position = WorldManager.cell_to_world(cell)
	
	# Get deterministic seed
	var seed_value = _get_deterministic_seed(cell)
	
	# Create planet data using the generator
	var planet_data = planet_generator.generate_planet(entity_id, position, seed_value, theme_id, false)
	
	# Override gaseous flag if specified
	if is_gaseous != planet_data.is_gaseous:
		planet_data.is_gaseous = is_gaseous
		planet_data.planet_category = PlanetData.PlanetCategory.GASEOUS if is_gaseous else PlanetData.PlanetCategory.TERRAN
	
	# Set grid cell
	planet_data.grid_cell = cell
	
	return planet_data

# Generate asteroid field data for a cell
func _generate_asteroid_field_at_cell(cell: Vector2i) -> AsteroidFieldData:
	# Get a deterministic entity ID
	var entity_id = _get_deterministic_entity_id(cell)
	
	# Calculate world position from cell
	var position = WorldManager.cell_to_world(cell)
	
	# Get deterministic seed
	var seed_value = _get_deterministic_seed(cell, 5000)  # Offset for asteroid fields
	
	# Create and configure field data
	var field_data = asteroid_generator.generate_asteroid_field(entity_id, position, seed_value)
	
	# Set grid cell
	field_data.grid_cell = cell
	
	# Generate asteroids for the field
	asteroid_generator.populate_asteroid_field(field_data, null)
	
	return field_data

# Get a deterministic entity ID for a cell
func _get_deterministic_entity_id(cell: Vector2i) -> int:
	# Use a formula that ensures unique IDs for each cell
	return 1000 + (cell.x * 100) + cell.y

# Get a deterministic seed for a cell (with optional offset for different entity types)
func _get_deterministic_seed(cell: Vector2i, offset: int = 0) -> int:
	var base_seed = 12345
	
	# Use seed from game settings if available
	if _game_settings:
		base_seed = _game_settings.get_seed()
	elif has_node("/root/SeedManager"):
		base_seed = SeedManager.get_seed()
	
	# Generate deterministic seed from cell coordinates
	return base_seed + (cell.x * 1000) + (cell.y * 100) + offset

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
	
	if not fragment_spawner._initialized:
		await fragment_spawner.spawner_ready
