extends RefCounted
class_name StationDataGenerator

# Station generation constants
const STATION_SIZE_MIN = 0.8
const STATION_SIZE_MAX = 1.2
const ROTATION_SPEED_MIN = -0.1
const ROTATION_SPEED_MAX = 0.1
const DEFENSE_RADIUS_MIN = 400.0
const DEFENSE_RADIUS_MAX = 600.0

# Station name prefixes
const STATION_TYPE_PREFIXES = {
	StationData.StationType.TRADING: ["Trading", "Market", "Commerce", "Exchange"],
	StationData.StationType.RESEARCH: ["Research", "Science", "Laboratory", "Analysis"],
	StationData.StationType.MILITARY: ["Military", "Defense", "Security", "Command"],
	StationData.StationType.MINING: ["Mining", "Extraction", "Resource", "Refinery"]
}

# Resources for trading (copied from ResourceManager)
const RESOURCE_TYPES = {
	"CREDITS": 0,
	"FUEL": 1,
	"METAL_ORE": 2,
	"PRECIOUS_METALS": 3,
	"CRYSTALS": 4,
	"ORGANIC_MATTER": 5,
	"TECHNOLOGY_PARTS": 6,
	"WEAPONS_COMPONENTS": 7,
	"MEDICAL_SUPPLIES": 8,
	"LUXURY_GOODS": 9
}

# Internal state
var _seed_value: int = 0
var _rng: RandomNumberGenerator

# Initialize with seed
func _init(seed_value: int = 0):
	_seed_value = seed_value
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value

# Generate a station with the given parameters
func generate_station(entity_id: int, position: Vector2, seed_value: int, 
					  station_type: int = StationData.StationType.TRADING) -> StationData:
	# Set seed for deterministic generation
	_rng.seed = seed_value
	
	# Create station data
	var station_data = StationData.new(
		entity_id,
		position,
		seed_value,
		station_type
	)
	
	# Generate station name
	station_data.station_name = _generate_station_name(station_type)
	
	# Set station level (1-3)
	station_data.level = _rng.randi_range(1, 3)
	
	# Set visual properties
	station_data.texture_seed = seed_value
	station_data.rotation_speed = _rng.randf_range(ROTATION_SPEED_MIN, ROTATION_SPEED_MAX)
	station_data.size = _rng.randf_range(STATION_SIZE_MIN, STATION_SIZE_MAX)
	
	# Set defense properties
	station_data.defense_radius = _rng.randf_range(DEFENSE_RADIUS_MIN, DEFENSE_RADIUS_MAX)
	station_data.defense_level = _rng.randi_range(1, 3)
	station_data.hostility = _rng.randf_range(0.0, 0.3)  # Generally non-hostile
	
	# Generate market data
	_generate_market_data(station_data)
	
	return station_data

# Generate a name for the station
func _generate_station_name(station_type: int) -> String:
	# Get prefixes for this station type
	var prefixes = STATION_TYPE_PREFIXES.get(station_type, ["Station"])
	
	# Choose a random prefix
	var prefix = prefixes[_rng.randi() % prefixes.size()]
	
	# Generate designation (letter and number)
	var letter = char(65 + _rng.randi() % 26)  # A-Z
	var number = _rng.randi_range(1, 999)
	var designation = "%s-%d" % [letter, number]
	
	return "%s Station %s" % [prefix, designation]

# Generate market data for the station
func _generate_market_data(station_data: StationData) -> void:
	# Different resource profiles based on station type
	match station_data.station_type:
		StationData.StationType.TRADING:
			# Trading stations sell and buy most resources at moderate prices
			for resource_id in range(1, 10):  # Skip credits (0)
				var sell_modifier = _rng.randf_range(1.1, 1.3)
				var buy_modifier = _rng.randf_range(0.7, 0.9)
				
				station_data.add_sell_resource(resource_id, sell_modifier)
				station_data.add_buy_resource(resource_id, buy_modifier)
		
		StationData.StationType.MINING:
			# Mining stations sell raw materials at good prices
			station_data.add_sell_resource(RESOURCE_TYPES.METAL_ORE, _rng.randf_range(0.8, 0.9))
			station_data.add_sell_resource(RESOURCE_TYPES.PRECIOUS_METALS, _rng.randf_range(0.9, 1.0))
			station_data.add_sell_resource(RESOURCE_TYPES.FUEL, _rng.randf_range(0.9, 1.0))
			
			# Buy processed goods
			station_data.add_buy_resource(RESOURCE_TYPES.TECHNOLOGY_PARTS, _rng.randf_range(1.1, 1.2))
			station_data.add_buy_resource(RESOURCE_TYPES.WEAPONS_COMPONENTS, _rng.randf_range(1.1, 1.3))
			station_data.add_buy_resource(RESOURCE_TYPES.LUXURY_GOODS, _rng.randf_range(1.2, 1.4))
		
		StationData.StationType.RESEARCH:
			# Research stations sell technology and medical supplies
			station_data.add_sell_resource(RESOURCE_TYPES.TECHNOLOGY_PARTS, _rng.randf_range(0.8, 0.9))
			station_data.add_sell_resource(RESOURCE_TYPES.MEDICAL_SUPPLIES, _rng.randf_range(0.8, 0.9))
			
			# Buy raw materials for research
			station_data.add_buy_resource(RESOURCE_TYPES.CRYSTALS, _rng.randf_range(1.2, 1.4))
			station_data.add_buy_resource(RESOURCE_TYPES.ORGANIC_MATTER, _rng.randf_range(1.1, 1.3))
			station_data.add_buy_resource(RESOURCE_TYPES.PRECIOUS_METALS, _rng.randf_range(1.1, 1.2))
		
		StationData.StationType.MILITARY:
			# Military stations sell weapons and military technology
			station_data.add_sell_resource(RESOURCE_TYPES.WEAPONS_COMPONENTS, _rng.randf_range(0.8, 0.9))
			station_data.add_sell_resource(RESOURCE_TYPES.TECHNOLOGY_PARTS, _rng.randf_range(0.9, 1.0))
			station_data.add_sell_resource(RESOURCE_TYPES.FUEL, _rng.randf_range(0.9, 1.0))
			
			# Buy strategic resources
			station_data.add_buy_resource(RESOURCE_TYPES.METAL_ORE, _rng.randf_range(1.0, 1.2))
			station_data.add_buy_resource(RESOURCE_TYPES.PRECIOUS_METALS, _rng.randf_range(1.0, 1.2))
			station_data.add_buy_resource(RESOURCE_TYPES.CRYSTALS, _rng.randf_range(1.1, 1.3))
	
	# Generate available upgrades (appropriate for station type)
	_generate_available_upgrades(station_data)

# Generate available upgrades for the station
func _generate_available_upgrades(station_data: StationData) -> void:
	var num_upgrades = _rng.randi_range(2, 5)
	var upgrade_pool = []
	
	# Create pool of upgrades based on station type
	match station_data.station_type:
		StationData.StationType.TRADING:
			# Trading stations offer a variety
			upgrade_pool = range(0, 12)
		
		StationData.StationType.MINING:
			# Mining stations focus on shields and basic weaponry
			upgrade_pool = [0, 1, 2, 4, 5, 8, 9]
		
		StationData.StationType.RESEARCH:
			# Research stations offer advanced upgrades
			upgrade_pool = [2, 3, 6, 7, 10, 11]
		
		StationData.StationType.MILITARY:
			# Military stations focus on weapons and movement
			upgrade_pool = [0, 1, 2, 3, 8, 9, 10, 11]
	
	# Shuffle the pool
	upgrade_pool.shuffle()
	
	# Take the first n items
	for i in range(min(num_upgrades, upgrade_pool.size())):
		station_data.add_available_upgrade(upgrade_pool[i])
