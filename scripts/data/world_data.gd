extends Resource
class_name WorldData

# World generation seed
var seed_value: int = 0
var seed_hash: String = ""

# World properties
var grid_size: int = 10
var grid_cell_size: int = 1024

# Player information
var player_start_cell: Vector2i = Vector2i(-1, -1)
var player_start_position: Vector2 = Vector2.ZERO

# Entity collections
var planets: Array = []
var asteroid_fields: Array = []

# Entity IDs - for tracking
var next_entity_id: int = 1
var entity_lookup: Dictionary = {}

# Fragment patterns for runtime use
var asteroid_fragment_patterns: Array = []

func _init(p_seed: int = 0, p_grid_size: int = 10, p_cell_size: int = 1024) -> void:
	seed_value = p_seed
	grid_size = p_grid_size
	grid_cell_size = p_cell_size
	
	# Generate hash from seed for display purposes
	seed_hash = _generate_seed_hash(seed_value)

# Get a unique entity ID
func get_next_entity_id() -> int:
	var id = next_entity_id
	next_entity_id += 1
	return id

# Register an entity for lookup
func register_entity(entity_data: EntityData) -> void:
	entity_lookup[entity_data.entity_id] = entity_data

# Get entity by ID
func get_entity(entity_id: int) -> EntityData:
	if entity_lookup.has(entity_id):
		return entity_lookup[entity_id]
	return null

# Add planet to the world
func add_planet(planet_data: PlanetData) -> void:
	if planet_data.entity_id == 0:
		planet_data.entity_id = get_next_entity_id()
	planets.append(planet_data)
	register_entity(planet_data)
	
	# Register all moons
	for moon in planet_data.moons:
		if moon.entity_id == 0:
			moon.entity_id = get_next_entity_id()
		register_entity(moon)

# Add asteroid field to the world
func add_asteroid_field(field_data: AsteroidFieldData) -> void:
	if field_data.entity_id == 0:
		field_data.entity_id = get_next_entity_id()
	asteroid_fields.append(field_data)
	register_entity(field_data)
	
	# Register all asteroids in the field
	for asteroid in field_data.asteroids:
		if asteroid.entity_id == 0:
			asteroid.entity_id = get_next_entity_id()
		register_entity(asteroid)
		asteroid.field_id = field_data.entity_id

# Get all planets in a specific cell
func get_planets_in_cell(cell: Vector2i) -> Array:
	var result = []
	for planet in planets:
		if planet.grid_cell == cell:
			result.append(planet)
	return result

# Get all asteroid fields in a specific cell
func get_asteroid_fields_in_cell(cell: Vector2i) -> Array:
	var result = []
	for field in asteroid_fields:
		if field.grid_cell == cell:
			result.append(field)
	return result

# Get all entities in a specific cell
func get_entities_in_cell(cell: Vector2i) -> Array:
	var result = []
	result.append_array(get_planets_in_cell(cell))
	result.append_array(get_asteroid_fields_in_cell(cell))
	return result

# Check if a cell is occupied
func is_cell_occupied(cell: Vector2i) -> bool:
	return not get_entities_in_cell(cell).is_empty()

# Find the nearest entity of a specific type to a position
func find_nearest_entity(position: Vector2, entity_type: String = "") -> EntityData:
	var nearest_entity = null
	var nearest_distance = INF
	
	# Determine which arrays to search based on type
	var entities_to_check = []
	
	if entity_type == "planet" or entity_type.is_empty():
		entities_to_check.append_array(planets)
	
	if entity_type == "asteroid_field" or entity_type.is_empty():
		entities_to_check.append_array(asteroid_fields)
	
	# Find the nearest entity
	for entity in entities_to_check:
		var distance = position.distance_to(entity.position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_entity = entity
	
	return nearest_entity

# Generate a seed hash for display
func _generate_seed_hash(seed_val: int) -> String:
	var characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var hash_string = ""
	var temp_seed = seed_val
	
	for i in range(6):
		var index = temp_seed % characters.length()
		hash_string += characters[index]
		temp_seed = int(temp_seed / float(characters.length()))
	
	return hash_string

# Create a deep copy of this world data
func duplicate() -> WorldData:
	var copy = WorldData.new(seed_value, grid_size, grid_cell_size)
	copy.seed_hash = seed_hash
	copy.player_start_cell = player_start_cell
	copy.player_start_position = player_start_position
	copy.next_entity_id = next_entity_id
	
	# Duplicate all entities
	for planet in planets:
		var planet_copy = planet.duplicate()
		copy.add_planet(planet_copy)
	
	for field in asteroid_fields:
		var field_copy = field.duplicate()
		copy.add_asteroid_field(field_copy)
	
	# Duplicate asteroid fragment patterns
	copy.asteroid_fragment_patterns = []
	for pattern in asteroid_fragment_patterns:
		copy.asteroid_fragment_patterns.append(pattern.duplicate(true))
	
	return copy

# Serialization helper
func to_dict() -> Dictionary:
	var result = {
		"seed_value": seed_value,
		"seed_hash": seed_hash,
		"grid_size": grid_size,
		"grid_cell_size": grid_cell_size,
		"player_start_cell": {"x": player_start_cell.x, "y": player_start_cell.y},
		"player_start_position": {"x": player_start_position.x, "y": player_start_position.y},
		"next_entity_id": next_entity_id,
		"planets": [],
		"asteroid_fields": []
	}
	
	# Serialize planets
	for planet in planets:
		result.planets.append(planet.to_dict())
	
	# Serialize asteroid fields
	for field in asteroid_fields:
		result.asteroid_fields.append(field.to_dict())
	
	# Fragment patterns are not serialized (regenerated on load)
	
	return result

# Deserialization helper
static func from_dict(data: Dictionary) -> WorldData:
	var world_data = WorldData.new(
		data.get("seed_value", 0),
		data.get("grid_size", 10),
		data.get("grid_cell_size", 1024)
	)
	
	world_data.seed_hash = data.get("seed_hash", "")
	
	var cell = data.get("player_start_cell", {"x": -1, "y": -1})
	world_data.player_start_cell = Vector2i(cell.get("x", -1), cell.get("y", -1))
	
	var pos = data.get("player_start_position", {"x": 0, "y": 0})
	world_data.player_start_position = Vector2(pos.get("x", 0), pos.get("y", 0))
	
	world_data.next_entity_id = data.get("next_entity_id", 1)
	
	# Deserialize planets
	var planets_data = data.get("planets", [])
	for planet_dict in planets_data:
		var planet = PlanetData.from_dict(planet_dict)
		world_data.add_planet(planet)
	
	# Deserialize asteroid fields
	var fields_data = data.get("asteroid_fields", [])
	for field_dict in fields_data:
		var field = AsteroidFieldData.from_dict(field_dict)
		world_data.add_asteroid_field(field)
	
	# Regenerate fragment patterns (not serialized)
	
	return world_data

# Save world data to file
func save_to_file(filepath: String) -> Error:
	var data = to_dict()
	var file = FileAccess.open(filepath, FileAccess.WRITE)
	if file:
		file.store_var(data)
		return OK
	return FAILED

# Load world data from file
static func load_from_file(filepath: String) -> WorldData:
	if FileAccess.file_exists(filepath):
		var file = FileAccess.open(filepath, FileAccess.READ)
		if file:
			var data = file.get_var()
			if data is Dictionary:
				return from_dict(data)
	return null
