# autoload/resources.gd
extends Node
class_name ResourceManager

signal resource_added(resource_id, amount)
signal resource_removed(resource_id, amount)
signal resource_changed(resource_id, new_amount, old_amount)
signal cargo_capacity_changed(new_capacity, old_capacity)

# Resource types
enum ResourceType {
	CREDITS,
	FUEL,
	METAL_ORE,
	PRECIOUS_METALS,
	CRYSTALS,
	ORGANIC_MATTER,
	TECHNOLOGY_PARTS,
	WEAPONS_COMPONENTS,
	MEDICAL_SUPPLIES,
	LUXURY_GOODS
}

# Resource metadata
var resource_data = {
	ResourceType.CREDITS: {
		"name": "Credits",
		"description": "Universal currency used across the galaxy",
		"icon": null,
		"base_value": 1.0,  # Base value for trading
		"base_weight": 0.0,  # Credits don't take cargo space
		"is_currency": true
	},
	ResourceType.FUEL: {
		"name": "Fuel",
		"description": "Standard ship fuel for interplanetary travel",
		"icon": null,
		"base_value": 5.0,
		"base_weight": 0.1
	},
	ResourceType.METAL_ORE: {
		"name": "Metal Ore",
		"description": "Raw metal ore from asteroid mining",
		"icon": null,
		"base_value": 10.0,
		"base_weight": 2.0
	},
	ResourceType.PRECIOUS_METALS: {
		"name": "Precious Metals",
		"description": "High-value refined metals",
		"icon": null,
		"base_value": 50.0,
		"base_weight": 1.0
	},
	ResourceType.CRYSTALS: {
		"name": "Crystals",
		"description": "Rare crystals used in advanced technology",
		"icon": null,
		"base_value": 75.0,
		"base_weight": 0.5
	},
	ResourceType.ORGANIC_MATTER: {
		"name": "Organic Matter",
		"description": "Biological resources for various uses",
		"icon": null,
		"base_value": 15.0,
		"base_weight": 1.5
	},
	ResourceType.TECHNOLOGY_PARTS: {
		"name": "Technology Parts",
		"description": "Components for building advanced systems",
		"icon": null,
		"base_value": 40.0,
		"base_weight": 0.8
	},
	ResourceType.WEAPONS_COMPONENTS: {
		"name": "Weapons Components",
		"description": "Parts for manufacturing weapons",
		"icon": null,
		"base_value": 60.0,
		"base_weight": 1.2
	},
	ResourceType.MEDICAL_SUPPLIES: {
		"name": "Medical Supplies",
		"description": "Essential medical equipment and medicines",
		"icon": null,
		"base_value": 35.0,
		"base_weight": 0.7
	},
	ResourceType.LUXURY_GOODS: {
		"name": "Luxury Goods",
		"description": "High-value luxury items",
		"icon": null,
		"base_value": 100.0,
		"base_weight": 0.3
	}
}

# Inventory and capacity
var inventory: Dictionary = {}  # resource_id -> amount
var cargo_capacity: float = 100.0
var used_capacity: float = 0.0

# Market price fluctuations for different stations/regions
var market_modifiers: Dictionary = {}  # station_id -> { resource_id -> price_modifier }

func _ready() -> void:
	# Initialize inventory with zero amounts
	for resource_id in resource_data:
		inventory[resource_id] = 0.0

# Add resources to inventory
func add_resource(resource_id: int, amount: float) -> bool:
	if amount <= 0:
		return false
	
	var old_amount = inventory[resource_id]
	
	# Check cargo capacity for non-currency resources
	if not resource_data[resource_id].is_currency:
		var weight_per_unit = resource_data[resource_id].base_weight
		var additional_weight = amount * weight_per_unit
		
		if used_capacity + additional_weight > cargo_capacity:
			# Not enough cargo space
			return false
		
		used_capacity += additional_weight
	
	# Add the resource
	inventory[resource_id] += amount
	
	# Emit signals
	resource_added.emit(resource_id, amount)
	resource_changed.emit(resource_id, inventory[resource_id], old_amount)
	
	return true

# Remove resources from inventory
func remove_resource(resource_id: int, amount: float) -> bool:
	if amount <= 0 or inventory[resource_id] < amount:
		return false
	
	var old_amount = inventory[resource_id]
	
	# Remove the resource
	inventory[resource_id] -= amount
	
	# Update used capacity for non-currency resources
	if not resource_data[resource_id].is_currency:
		var weight_per_unit = resource_data[resource_id].base_weight
		var reduced_weight = amount * weight_per_unit
		used_capacity -= reduced_weight
	
	# Emit signals
	resource_removed.emit(resource_id, amount)
	resource_changed.emit(resource_id, inventory[resource_id], old_amount)
	
	return true

# Set cargo capacity
func set_cargo_capacity(new_capacity: float) -> void:
	if new_capacity == cargo_capacity:
		return
	
	var old_capacity = cargo_capacity
	cargo_capacity = max(0.0, new_capacity)
	
	cargo_capacity_changed.emit(cargo_capacity, old_capacity)

# Get available cargo space
func get_available_cargo_space() -> float:
	return cargo_capacity - used_capacity

# Check if there's enough cargo space for a resource amount
func has_cargo_space_for(resource_id: int, amount: float) -> bool:
	if resource_data[resource_id].is_currency:
		return true  # Currency doesn't take cargo space
	
	var weight_per_unit = resource_data[resource_id].base_weight
	var required_space = amount * weight_per_unit
	
	return get_available_cargo_space() >= required_space

# Get the current amount of a resource
func get_resource_amount(resource_id: int) -> float:
	return inventory[resource_id]

# Check if the player has enough of a resource
func has_resource(resource_id: int, amount: float) -> bool:
	return inventory[resource_id] >= amount

# Get the total value of cargo (excluding credits)
func get_total_cargo_value() -> float:
	var total_value = 0.0
	
	for resource_id in inventory:
		if resource_id != ResourceType.CREDITS:
			total_value += inventory[resource_id] * resource_data[resource_id].base_value
	
	return total_value

# Get the resource name
func get_resource_name(resource_id: int) -> String:
	if resource_data.has(resource_id):
		return resource_data[resource_id].name
	return "Unknown Resource"

# Trade resources with a station
func trade_with_station(station_id: String, buy_resources: Dictionary, sell_resources: Dictionary) -> bool:
	# First calculate the total transaction
	var total_cost = 0.0
	var total_earnings = 0.0
	
	# Calculate cost of buying resources
	for resource_id in buy_resources:
		var amount = buy_resources[resource_id]
		var price_per_unit = get_resource_price(resource_id, station_id)
		total_cost += amount * price_per_unit
	
	# Calculate earnings from selling resources
	for resource_id in sell_resources:
		var amount = sell_resources[resource_id]
		var price_per_unit = get_resource_price(resource_id, station_id)
		total_earnings += amount * price_per_unit
	
	# Check if the player has enough credits
	if total_cost > inventory[ResourceType.CREDITS]:
		return false
	
	# Check if the player has enough resources to sell
	for resource_id in sell_resources:
		if not has_resource(resource_id, sell_resources[resource_id]):
			return false
	
	# Check cargo capacity for buying resources
	var required_capacity = 0.0
	for resource_id in buy_resources:
		if not resource_data[resource_id].is_currency:
			required_capacity += buy_resources[resource_id] * resource_data[resource_id].base_weight
	
	var freed_capacity = 0.0
	for resource_id in sell_resources:
		if not resource_data[resource_id].is_currency:
			freed_capacity += sell_resources[resource_id] * resource_data[resource_id].base_weight
	
	if get_available_cargo_space() + freed_capacity < required_capacity:
		return false
	
	# Execute the trade
	var credits_change = total_earnings - total_cost
	
	# Update credits
	if credits_change != 0:
		if credits_change > 0:
			add_resource(ResourceType.CREDITS, credits_change)
		else:
			remove_resource(ResourceType.CREDITS, -credits_change)
	
	# Remove sold resources
	for resource_id in sell_resources:
		remove_resource(resource_id, sell_resources[resource_id])
	
	# Add bought resources
	for resource_id in buy_resources:
		add_resource(resource_id, buy_resources[resource_id])
	
	return true

# Set market price modifiers for a station
func set_station_market_modifiers(station_id: String, modifiers: Dictionary) -> void:
	market_modifiers[station_id] = modifiers

# Get the price of a resource at a specific station
func get_resource_price(resource_id: int, station_id: String = "") -> float:
	var base_price = resource_data[resource_id].base_value
	
	if station_id.is_empty() or not market_modifiers.has(station_id):
		return base_price
	
	var station_modifiers = market_modifiers[station_id]
	
	if not station_modifiers.has(resource_id):
		return base_price
	
	return base_price * station_modifiers[resource_id]
