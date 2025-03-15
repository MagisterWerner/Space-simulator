# scripts/data/world_data.gd
# Enhanced to serve as the central repository for all world data

extends Resource
class_name WorldData

# World generation seed and metadata
var seed_value: int = 0
var seed_hash: String = ""
var generation_timestamp: int = 0

# World properties
var grid_size: int = 10
var grid_cell_size: int = 1024

# Player information
var player_start_cell: Vector2i = Vector2i(-1, -1)
var player_start_position: Vector2 = Vector2.ZERO

# Entity collections - optimized with key access
var planets: Dictionary = {} # entity_id -> PlanetData
var asteroid_fields: Dictionary = {} # entity_id -> AsteroidFieldData
var asteroids: Dictionary = {} # entity_id -> AsteroidData
var stations: Dictionary = {} # entity_id -> StationData

# Cell tracking - what's in each cell?
var cell_contents: Dictionary = {} # Vector2i -> Array of entity IDs

# Generation status tracking - which cells have been generated?
var generated_cells: Dictionary = {} # Vector2i -> generation status
var generation_queue: Array[Vector2i] = []

# Entity IDs
var next_entity_id: int = 1

# Centralized method to add an entity and track its cell location
func add_entity(entity_data: EntityData) -> void:
	# If entity has no ID, assign one
	if entity_data.entity_id == 0:
		entity_data.entity_id = get_next_entity_id()
	
	# Store in appropriate collection based on type
	match entity_data.entity_type:
		"planet":
			planets[entity_data.entity_id] = entity_data
		"asteroid_field":
			asteroid_fields[entity_data.entity_id] = entity_data
		"asteroid":
			asteroids[entity_data.entity_id] = entity_data
		"station":
			stations[entity_data.entity_id] = entity_data
	
	# Track in cell contents
	var cell = entity_data.grid_cell
	if cell != Vector2i(-1, -1):
		if not cell_contents.has(cell):
			cell_contents[cell] = []
		cell_contents[cell].append(entity_data.entity_id)

# Get all entities in a specific cell
func get_entities_in_cell(cell: Vector2i) -> Array:
	if not cell_contents.has(cell):
		return []
	
	var result = []
	for entity_id in cell_contents[cell]:
		var entity_data = get_entity_by_id(entity_id)
		if entity_data:
			result.append(entity_data)
	
	return result

# Get entity by ID with type checking
func get_entity_by_id(entity_id: int) -> EntityData:
	# Check each collection
	if planets.has(entity_id):
		return planets[entity_id]
	elif asteroid_fields.has(entity_id):
		return asteroid_fields[entity_id]
	elif asteroids.has(entity_id):
		return asteroids[entity_id]
	elif stations.has(entity_id):
		return stations[entity_id]
	
	return null

# Mark a cell as generated
func mark_cell_generated(cell: Vector2i, status: int = 1) -> void:
	generated_cells[cell] = status
	# Remove from queue if present
	var index = generation_queue.find(cell)
	if index >= 0:
		generation_queue.remove_at(index)

# Is a cell generated?
func is_cell_generated(cell: Vector2i) -> bool:
	return generated_cells.has(cell) and generated_cells[cell] > 0

# Get a unique entity ID
func get_next_entity_id() -> int:
	var id = next_entity_id
	next_entity_id += 1
	return id
