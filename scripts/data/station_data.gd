extends EntityData
class_name StationData

# Station types
enum StationType {
	TRADING,
	MINING,
	RESEARCH,
	MILITARY,
	SHIPYARD
}

# Station properties
var station_type: int = StationType.TRADING
var rotation_speed: float = 0.0
var docking_slots: int = 2
var defense_rating: int = 1

# Trading resources
var available_resources: Dictionary = {}
var resource_prices: Dictionary = {}
var resource_quantities: Dictionary = {}

# Services
var offers_refueling: bool = true
var offers_repairs: bool = true
var offers_upgrades: bool = false
var upgrade_types_available: Array = []

# Visual properties
var visual_variant: int = 0
var has_external_lights: bool = true
var light_color: Color = Color(1.0, 0.8, 0.2, 1.0)

func _init() -> void:
	super._init()
	entity_type = "station"

# Generate station resources based on type
func generate_resources(rng: RandomNumberGenerator) -> void:
	available_resources.clear()
	resource_prices.clear()
	resource_quantities.clear()
	
	match station_type:
		StationType.TRADING:
			# Trading stations have most resources
			for i in range(ResourceManager.ResourceType.size()):
				if i != ResourceManager.ResourceType.CREDITS:
					available_resources[i] = true
					resource_prices[i] = rng.randf_range(0.8, 1.2)
					resource_quantities[i] = rng.randi_range(50, 200)
					
		StationType.MINING:
			# Mining stations focus on raw materials
			available_resources[ResourceManager.ResourceType.METAL_ORE] = true
			available_resources[ResourceManager.ResourceType.PRECIOUS_METALS] = true
			available_resources[ResourceManager.ResourceType.CRYSTALS] = true
			
			resource_prices[ResourceManager.ResourceType.METAL_ORE] = rng.randf_range(0.7, 0.9)
			resource_prices[ResourceManager.ResourceType.PRECIOUS_METALS] = rng.randf_range(0.8, 1.0)
			resource_prices[ResourceManager.ResourceType.CRYSTALS] = rng.randf_range(0.8, 1.0)
			
			resource_quantities[ResourceManager.ResourceType.METAL_ORE] = rng.randi_range(200, 500)
			resource_quantities[ResourceManager.ResourceType.PRECIOUS_METALS] = rng.randi_range(100, 300)
			resource_quantities[ResourceManager.ResourceType.CRYSTALS] = rng.randi_range(50, 150)
			
		# Add similar cases for other station types
		_:
			# Default case
			available_resources[ResourceManager.ResourceType.FUEL] = true
			resource_prices[ResourceManager.ResourceType.FUEL] = rng.randf_range(0.9, 1.1)
			resource_quantities[ResourceManager.ResourceType.FUEL] = rng.randi_range(100, 300)

# Override to implement a proper copy
func duplicate() -> StationData:
	var copy = super.duplicate() as StationData
	copy.station_type = station_type
	copy.rotation_speed = rotation_speed
	copy.docking_slots = docking_slots
	copy.defense_rating = defense_rating
	copy.available_resources = available_resources.duplicate()
	copy.resource_prices = resource_prices.duplicate()
	copy.resource_quantities = resource_quantities.duplicate()
	copy.offers_refueling = offers_refueling
	copy.offers_repairs = offers_repairs
	copy.offers_upgrades = offers_upgrades
	copy.upgrade_types_available = upgrade_types_available.duplicate()
	copy.visual_variant = visual_variant
	copy.has_external_lights = has_external_lights
	copy.light_color = light_color
	return copy

func get_type_name() -> String:
	match station_type:
		StationType.TRADING: return "Trading Station"
		StationType.MINING: return "Mining Station"
		StationType.RESEARCH: return "Research Station"
		StationType.MILITARY: return "Military Outpost"
		StationType.SHIPYARD: return "Shipyard"
		_: return "Unknown Station"
