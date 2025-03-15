# scripts/spawners/station_spawner.gd
extends EntitySpawnerBase
class_name StationSpawner

# Station scene paths
const STATION_SCENE = "res://scenes/world/station.tscn"
const TRADING_STATION_SCENE = "res://scenes/world/trading_station.tscn"
const MILITARY_STATION_SCENE = "res://scenes/world/military_station.tscn"
const MINING_STATION_SCENE = "res://scenes/world/mining_station.tscn"
const RESEARCH_STATION_SCENE = "res://scenes/world/research_station.tscn"

# Station type mapping
var _station_type_scenes = {}

# Track spawned stations
var _stations = {}

func _load_common_scenes() -> void:
	# Load base station scene
	_load_scene("station", STATION_SCENE)
	
	# Load specialized stations if they exist
	if ResourceLoader.exists(TRADING_STATION_SCENE):
		_load_scene("trading_station", TRADING_STATION_SCENE)
	
	if ResourceLoader.exists(MILITARY_STATION_SCENE):
		_load_scene("military_station", MILITARY_STATION_SCENE)
	
	if ResourceLoader.exists(MINING_STATION_SCENE):
		_load_scene("mining_station", MINING_STATION_SCENE)
	
	if ResourceLoader.exists(RESEARCH_STATION_SCENE):
		_load_scene("research_station", RESEARCH_STATION_SCENE)
	
	# Map station types to scene keys
	_station_type_scenes[StationData.StationType.TRADING] = "trading_station"
	_station_type_scenes[StationData.StationType.MILITARY] = "military_station"
	_station_type_scenes[StationData.StationType.MINING] = "mining_station"
	_station_type_scenes[StationData.StationType.RESEARCH] = "research_station"

func spawn_entity(data: EntityData) -> Node:
	if not _initialized:
		await spawner_ready
	
	if data is StationData:
		return spawn_station(data)
	
	push_error("StationSpawner: Unknown data type for spawning")
	return null

func spawn_station(station_data: StationData) -> Node:
	# Determine which scene to use based on station type
	var scene_key = _station_type_scenes.get(station_data.station_type, "station")
	
	# Fall back to generic station if specialized one not available
	if not _scene_cache.has(scene_key):
		scene_key = "station"
		
		# If no station scene available at all, return error
		if not _scene_cache.has(scene_key):
			push_error("StationSpawner: No station scenes available")
			return null
	
	# Instantiate the station
	var station = _scene_cache[scene_key].instantiate()
	add_child(station)
	
	# Set position
	station.global_position = station_data.position
	
	# Configure using initialize method if available
	if station.has_method("initialize"):
		station.initialize(station_data.seed_value)
	
	# Set basic properties directly if needed
	if has_property(station, "station_type"):
		station.station_type = station_data.station_type
	
	if has_property(station, "station_name"):
		station.station_name = station_data.station_name
	
	if has_property(station, "level"):
		station.level = station_data.level
	
	if has_property(station, "size"):
		station.size = station_data.size
	
	if has_property(station, "rotation_speed"):
		station.rotation_speed = station_data.rotation_speed
	
	# Configure market data if method exists
	if station.has_method("set_market_data"):
		station.set_market_data(
			station_data.sells_resources, 
			station_data.buys_resources, 
			station_data.available_upgrades
		)
	
	# Register with entity manager
	register_entity(station, "station", station_data)
	
	# Track in our internal map
	_stations[station_data.entity_id] = station
	
	return station

# Utility function to create a station at a specific grid cell
func spawn_station_at_cell(cell: Vector2i, station_type: int = StationData.StationType.TRADING) -> Node:
	# Create a new station data
	var entity_id = 1
	if _entity_manager and _entity_manager.has_method("get_next_entity_id"):
		entity_id = _entity_manager.get_next_entity_id()
	
	# Calculate world position from cell
	var position = _get_cell_world_position(cell)
	
	# Add slight random offset
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var cell_size = 1024
	if _game_settings:
		cell_size = _game_settings.grid_cell_size
	
	var offset = Vector2(
		rng.randf_range(-cell_size/4.0, cell_size/4.0),
		rng.randf_range(-cell_size/4.0, cell_size/4.0)
	)
	position += offset
	
	# Create seed
	var seed_value = 0
	if _game_settings:
		var base_seed = _game_settings.get_seed()
		seed_value = base_seed + (cell.x * 1000) + (cell.y * 100) + 8000  # Offset for stations
	
	# Create station data
	var station_data = StationData.new(entity_id, position, seed_value, station_type)
	
	# Generate name and market data
	station_data.station_name = station_data.generate_name()
	station_data.generate_market_data()
	
	# Set grid cell
	station_data.grid_cell = cell
	
	# Spawn the station
	return spawn_station(station_data)

# Get station name from a StationData.StationType
func get_station_type_name(station_type: int) -> String:
	match station_type:
		StationData.StationType.TRADING: return "Trading"
		StationData.StationType.MILITARY: return "Military"
		StationData.StationType.MINING: return "Mining"
		StationData.StationType.RESEARCH: return "Research"
		_: return "Unknown"
