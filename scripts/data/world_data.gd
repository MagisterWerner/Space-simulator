extends Resource
class_name WorldData

# World identification
var world_id: String = ""
var seed_value: int = 0
var seed_hash: String = ""

# World properties
var grid_size: int = 10
var grid_cell_size: int = 1024

# Player start information
var player_start_position: Vector2 = Vector2.ZERO
var player_start_cell: Vector2i = Vector2i(-1, -1)
var player_start_planet: PlanetData = null

# Entity collections
var entities: Array[EntityData] = []
var entity_map: Dictionary = {}  # Maps entity_id to entity data
var cell_entities: Dictionary = {}  # Maps grid_cell to array of entity_ids
var type_entities: Dictionary = {}  # Maps entity_type to array of entity_ids

# Cached information
var first_gaseous_planet: PlanetData = null
var player_credits: int = 1000
var player_starting_fuel: int = 100

# Generation metadata
var creation_timestamp: int = 0
var generation_time_ms: int = 0

func _init() -> void:
	# Generate unique ID for this world
	world_id = "world_" + str(Time.get_unix_time_from_system())
	creation_timestamp = Time.get_ticks_msec()

# Add an entity to the world data
func add_entity(entity: EntityData) -> void:
	# Add to main entity array
	entities.append(entity)
	
	# Add to lookup maps for faster access
	entity_map[entity.entity_id] = entity
	
	# Add to cell mapping
	if not cell_entities.has(entity.grid_cell):
		cell_entities[entity.grid_cell] = []
	cell_entities[entity.grid_cell].append(entity.entity_id)
	
	# Add to type mapping
	if not type_entities.has(entity.entity_type):
		type_entities[entity.entity_type] = []
	type_entities[entity.entity_type].append(entity.entity_id)
	
	# Update cached references
	if entity is PlanetData:
		if entity.is_player_starting_planet:
			player_start_planet = entity
			player_start_position = entity.world_position
			player_start_cell = entity.grid_cell
			
		if entity.is_gaseous() and not first_gaseous_planet:
			first_gaseous_planet = entity

# Get entity by ID
func get_entity(entity_id: int) -> EntityData:
	if entity_map.has(entity_id):
		return entity_map[entity_id]
	return null

# Get entities in a cell
func get_entities_in_cell(cell: Vector2i) -> Array[EntityData]:
	var result: Array[EntityData] = []
	
	if not cell_entities.has(cell):
		return result
		
	for entity_id in cell_entities[cell]:
		if entity_map.has(entity_id):
			result.append(entity_map[entity_id])
			
	return result

# Get entities of a specified type
func get_entities_by_type(type: String) -> Array[EntityData]:
	var result: Array[EntityData] = []
	
	if not type_entities.has(type):
		return result
		
	for entity_id in type_entities[type]:
		if entity_map.has(entity_id):
			result.append(entity_map[entity_id])
			
	return result

# Get planet entities (returns array of PlanetData)
func get_planets() -> Array[PlanetData]:
	var planets: Array[PlanetData] = []
	
	var planet_entities = get_entities_by_type("planet")
	for entity in planet_entities:
		if entity is PlanetData:
			planets.append(entity)
			
	return planets

# Generate a unique entity ID
func generate_entity_id() -> int:
	var highest_id = 0
	
	for entity in entities:
		if entity.entity_id > highest_id:
			highest_id = entity.entity_id
			
	return highest_id + 1

# Deep clone function
func clone() -> WorldData:
	var copy = get_script().new()
	copy.world_id = world_id
	copy.seed_value = seed_value
	copy.seed_hash = seed_hash
	copy.grid_size = grid_size
	copy.grid_cell_size = grid_cell_size
	copy.player_start_position = player_start_position
	copy.player_start_cell = player_start_cell
	copy.player_credits = player_credits
	copy.player_starting_fuel = player_starting_fuel
	copy.creation_timestamp = creation_timestamp
	copy.generation_time_ms = generation_time_ms
	
	# Clone entity collections
	for entity in entities:
		var entity_clone = entity.clone()
		copy.add_entity(entity_clone)
		
		# Set references correctly
		if entity is PlanetData and entity == player_start_planet:
			copy.player_start_planet = entity_clone
	
	return copy

# Save world data to a file
func save_to_file(filepath: String = "") -> bool:
	if filepath.is_empty():
		filepath = "user://worlds/" + world_id + ".world"
	
	# Ensure directory exists
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("user://worlds"):
		dir.make_dir("user://worlds")
	
	# Save resource
	var err = ResourceSaver.save(self, filepath)
	return err == OK

# Load world data from a file
static func load_from_file(filepath: String) -> WorldData:
	if not FileAccess.file_exists(filepath):
		push_error("World data file does not exist: " + filepath)
		return null
	
	var resource = ResourceLoader.load(filepath)
	if resource is WorldData:
		return resource
	
	push_error("Failed to load world data from file: " + filepath)
	return null
