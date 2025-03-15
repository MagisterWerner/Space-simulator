extends EntitySpawner
class_name StationSpawner

# Station-specific configuration
@export_category("Station Configuration")
@export var station_scene_path: String = "res://scenes/world/station.tscn"
@export var trading_station_scene_path: String = ""  # Optional specialized station types
@export var mining_station_scene_path: String = ""
@export var research_station_scene_path: String = ""
@export var military_station_scene_path: String = ""
@export var shipyard_scene_path: String = ""

# Debug Options
@export var debug_station_generation: bool = false

# Scene caches for specialized station types
var _type_scene_cache: Dictionary = {}

func _ready() -> void:
	entity_type = "station"
	scene_path = station_scene_path
	
	# Load the main station scene
	_load_scene()
	
	# Load specialized station scenes if provided
	_load_specialized_scenes()

# Load specialized station scenes
func _load_specialized_scenes() -> void:
	var specialized_paths = {
		StationData.StationType.TRADING: trading_station_scene_path,
		StationData.StationType.MINING: mining_station_scene_path,
		StationData.StationType.RESEARCH: research_station_scene_path,
		StationData.StationType.MILITARY: military_station_scene_path,
		StationData.StationType.SHIPYARD: shipyard_scene_path
	}
	
	for type in specialized_paths:
		var path = specialized_paths[type]
		if not path.is_empty() and ResourceLoader.exists(path):
			_type_scene_cache[type] = load(path)

# Override validation to check for station data
func _validate_entity_data(entity_data) -> bool:
	if not super._validate_entity_data(entity_data):
		return false
	
	# Verify this is a station
	if not entity_data is StationData:
		push_error("StationSpawner: Invalid entity data, expected StationData but got " + str(entity_data.get_class()))
		return false
	
	return true

# Override to provide specialized station scenes
func _get_entity() -> Node:
	# Base method creates based on scene_path, we defer to spawn_entity
	return null

# Override spawn_entity to handle station-specific logic
func spawn_entity(entity_data) -> Node:
	if not _validate_entity_data(entity_data):
		return null
	
	var station_data: StationData = entity_data
	var entity_id = station_data.entity_id
	
	# Get the appropriate scene based on station type
	var scene = _type_scene_cache.get(station_data.station_type, _scene_cache)
	
	if not scene:
		push_error("StationSpawner: No scene available for station type: " + str(station_data.station_type))
		return null
	
	# Instance the station
	var station = scene.instantiate()
	add_child(station)
	
	# Position the station
	station.global_position = station_data.world_position
	
	# Configure the station
	_configure_station(station, station_data)
	
	# Register with EntityManager if enabled
	if auto_register_with_entity_manager and _entity_manager and _entity_manager.has_method("register_entity"):
		_entity_manager.register_entity(station, entity_type)
	
	# Track the entity
	_entity_map[entity_id] = station
	_data_map[entity_id] = station_data
	
	# Connect to signals
	if not station.tree_exiting.is_connected(_on_entity_tree_exiting):
		station.tree_exiting.connect(_on_entity_tree_exiting.bind(station))
	
	# Emit signal
	entity_spawned.emit(station, station_data)
	
	return station

# Configure a station with its data
func _configure_station(station: Node, station_data: StationData) -> void:
	# Set station name
	if "station_name" in station:
		station.station_name = station_data.entity_name
	
	# Set station type
	if "station_type" in station:
		station.station_type = station_data.station_type
	
	# Set rotation speed
	if "rotation_speed" in station:
		station.rotation_speed = station_data.rotation_speed
	
	# Set docking slots
	if "docking_slots" in station:
		station.docking_slots = station_data.docking_slots
	
	# Set defense rating
	if "defense_rating" in station:
		station.defense_rating = station_data.defense_rating
	
	# Set services
	if "offers_refueling" in station:
		station.offers_refueling = station_data.offers_refueling
	if "offers_repairs" in station:
		station.offers_repairs = station_data.offers_repairs
	if "offers_upgrades" in station:
		station.offers_upgrades = station_data.offers_upgrades
	
	# Set available upgrades
	if "upgrade_types_available" in station:
		station.upgrade_types_available = station_data.upgrade_types_available.duplicate()
	
	# Set visual properties
	if "visual_variant" in station:
		station.visual_variant = station_data.visual_variant
	if "has_external_lights" in station:
		station.has_external_lights = station_data.has_external_lights
	if "light_color" in station:
		station.light_color = station_data.light_color
	
	# Set trading resources
	if "available_resources" in station:
		station.available_resources = station_data.available_resources.duplicate()
	if "resource_prices" in station:
		station.resource_prices = station_data.resource_prices.duplicate()
	if "resource_quantities" in station:
		station.resource_quantities = station_data.resource_quantities.duplicate()
	
	# Call initialize method if available
	if station.has_method("initialize"):
		station.initialize(station_data.seed_value)
	
	# Set debug settings
	if "debug_mode" in station:
		station.debug_mode = debug_station_generation
