extends EntityData
class_name StationData

# Station types
enum StationType {
	TRADING,
	RESEARCH,
	MILITARY,
	MINING
}

# Core properties
var station_type: int = StationType.TRADING
var station_name: String = ""
var level: int = 1

# Visual properties
var texture_seed: int = 0
var rotation_speed: float = 0.0
var size: float = 1.0

# Trader properties
var sells_resources: Dictionary = {}  # Resource ID -> price modifier
var buys_resources: Dictionary = {}   # Resource ID -> price modifier
var available_upgrades: Array = []    # Upgrade IDs or names

# Defense properties
var defense_radius: float = 500.0
var defense_level: int = 1
var hostility: float = 0.0

func _init(p_entity_id: int = 0, p_position: Vector2 = Vector2.ZERO, p_seed: int = 0, p_type: int = StationType.TRADING) -> void:
	super._init(p_entity_id, "station", p_position, p_seed)
	station_type = p_type
	texture_seed = p_seed
	
	# Generate rotation speed based on seed (for visual effect)
	var rng = RandomNumberGenerator.new()
	rng.seed = p_seed
	rotation_speed = rng.randf_range(-0.1, 0.1)

# Get type name as string
func get_type_name() -> String:
	match station_type:
		StationType.TRADING: return "Trading"
		StationType.RESEARCH: return "Research"
		StationType.MILITARY: return "Military"
		StationType.MINING: return "Mining"
		_: return "Unknown"

# Generate a default name based on type and seed
func generate_name() -> String:
	if station_name.is_empty():
		var rng = RandomNumberGenerator.new()
		rng.seed = seed_value
		
		var prefix = get_type_name()
		
		# Generate designation (combination of letters and numbers)
		var designation = ""
		var letter = char(65 + rng.randi() % 26)  # A-Z
		var number = rng.randi_range(1, 999)
		designation = "%s-%d" % [letter, number]
		
		station_name = "%s Station %s" % [prefix, designation]
	
	return station_name

# Add a resource price modifier
func add_sell_resource(resource_id: int, price_modifier: float) -> void:
	sells_resources[resource_id] = price_modifier

func add_buy_resource(resource_id: int, price_modifier: float) -> void:
	buys_resources[resource_id] = price_modifier

# Add available upgrade
func add_available_upgrade(upgrade_id) -> void:
	if not available_upgrades.has(upgrade_id):
		available_upgrades.append(upgrade_id)

# Generate market prices based on seed
func generate_market_data() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# ResourceManager.ResourceType values (from your existing code)
	var resource_types = {
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
	
	# Trading stations sell and buy most resources
	if station_type == StationType.TRADING:
		# Sells all resources at slightly high prices
		for resource_id in resource_types.values():
			if resource_id != resource_types.CREDITS:  # Don't sell/buy credits
				var sell_modifier = rng.randf_range(1.1, 1.3)
				sells_resources[resource_id] = sell_modifier
				
				# Buy at slightly low prices
				var buy_modifier = rng.randf_range(0.7, 0.9)
				buys_resources[resource_id] = buy_modifier
	
	# Mining stations specialize in raw materials
	elif station_type == StationType.MINING:
		# Sells ore and metals at good prices
		sells_resources[resource_types.METAL_ORE] = rng.randf_range(0.8, 0.9)
		sells_resources[resource_types.PRECIOUS_METALS] = rng.randf_range(0.9, 1.0)
		sells_resources[resource_types.FUEL] = rng.randf_range(0.9, 1.0)
		
		# Buys processed goods
		buys_resources[resource_types.TECHNOLOGY_PARTS] = rng.randf_range(1.1, 1.2)
		buys_resources[resource_types.WEAPONS_COMPONENTS] = rng.randf_range(1.1, 1.3)
		buys_resources[resource_types.LUXURY_GOODS] = rng.randf_range(1.2, 1.4)
	
	# Research stations focus on high-tech and science
	elif station_type == StationType.RESEARCH:
		# Sells technology and medical supplies
		sells_resources[resource_types.TECHNOLOGY_PARTS] = rng.randf_range(0.8, 0.9)
		sells_resources[resource_types.MEDICAL_SUPPLIES] = rng.randf_range(0.8, 0.9)
		
		# Buys raw materials for research
		buys_resources[resource_types.CRYSTALS] = rng.randf_range(1.2, 1.4)
		buys_resources[resource_types.ORGANIC_MATTER] = rng.randf_range(1.1, 1.3)
		buys_resources[resource_types.PRECIOUS_METALS] = rng.randf_range(1.1, 1.2)
	
	# Military stations focus on weapons and defense
	elif station_type == StationType.MILITARY:
		# Sells weapons and military technology
		sells_resources[resource_types.WEAPONS_COMPONENTS] = rng.randf_range(0.8, 0.9)
		sells_resources[resource_types.TECHNOLOGY_PARTS] = rng.randf_range(0.9, 1.0)
		sells_resources[resource_types.FUEL] = rng.randf_range(0.9, 1.0)
		
		# Buys strategic resources
		buys_resources[resource_types.METAL_ORE] = rng.randf_range(1.0, 1.2)
		buys_resources[resource_types.PRECIOUS_METALS] = rng.randf_range(1.0, 1.2)
		buys_resources[resource_types.CRYSTALS] = rng.randf_range(1.1, 1.3)

# Override duplicate for proper copying
func duplicate() -> StationData:
	var copy = super.duplicate() as StationData
	
	# Core properties
	copy.station_type = station_type
	copy.station_name = station_name
	copy.level = level
	
	# Visual properties
	copy.texture_seed = texture_seed
	copy.rotation_speed = rotation_speed
	copy.size = size
	
	# Trader properties (deep copy)
	copy.sells_resources = sells_resources.duplicate()
	copy.buys_resources = buys_resources.duplicate()
	copy.available_upgrades = available_upgrades.duplicate()
	
	# Defense properties
	copy.defense_radius = defense_radius
	copy.defense_level = defense_level
	copy.hostility = hostility
	
	return copy

# Serialization helper
func to_dict() -> Dictionary:
	var base_dict = super.to_dict()
	
	var station_dict = {
		"station_type": station_type,
		"station_name": station_name,
		"level": level,
		"texture_seed": texture_seed,
		"rotation_speed": rotation_speed,
		"size": size,
		"sells_resources": sells_resources,
		"buys_resources": buys_resources,
		"available_upgrades": available_upgrades,
		"defense_radius": defense_radius,
		"defense_level": defense_level,
		"hostility": hostility
	}
	
	# Merge with base dictionary
	base_dict.merge(station_dict, true)
	return base_dict

# Deserialization helper
static func from_dict(data: Dictionary) -> StationData:
	var base_data = EntityData.from_dict(data)
	
	var station_data = StationData.new()
	station_data.entity_id = base_data.entity_id
	station_data.entity_type = base_data.entity_type
	station_data.position = base_data.position
	station_data.seed_value = base_data.seed_value
	station_data.grid_cell = base_data.grid_cell
	station_data.properties = base_data.properties
	
	# Station-specific properties
	station_data.station_type = data.get("station_type", StationType.TRADING)
	station_data.station_name = data.get("station_name", "")
	station_data.level = data.get("level", 1)
	
	# Visual properties
	station_data.texture_seed = data.get("texture_seed", station_data.seed_value)
	station_data.rotation_speed = data.get("rotation_speed", 0.0)
	station_data.size = data.get("size", 1.0)
	
	# Trader properties
	station_data.sells_resources = data.get("sells_resources", {}).duplicate()
	station_data.buys_resources = data.get("buys_resources", {}).duplicate()
	station_data.available_upgrades = data.get("available_upgrades", []).duplicate()
	
	# Defense properties
	station_data.defense_radius = data.get("defense_radius", 500.0)
	station_data.defense_level = data.get("defense_level", 1)
	station_data.hostility = data.get("hostility", 0.0)
	
	return station_data
