# autoload/resource_manager.gd
# ===========================
# Purpose:
#   Manages the player's resources, inventory, and trading system.
#   Handles resource types, quantities, and resource-related operations.
#   Updated to work with GameSettings for initial resource values.
#
# Interface:
#   Signals:
#     - resource_added(resource_id, amount)
#     - resource_removed(resource_id, amount)
#     - resource_changed(resource_id, new_amount, old_amount)
#     - cargo_capacity_changed(new_capacity, old_capacity)
#
#   Enums:
#     - ResourceType: CREDITS, FUEL, METAL_ORE, etc.
#
#   Resource Methods:
#     - add_resource(resource_id, amount)
#     - remove_resource(resource_id, amount)
#     - get_resource_amount(resource_id)
#     - has_resource(resource_id, amount)
#     - get_resource_name(resource_id)

extends Node

signal resource_added(resource_id, amount)
signal resource_removed(resource_id, amount)
signal resource_changed(resource_id, new_amount, old_amount)
signal cargo_capacity_changed(new_capacity, old_capacity)

# Reference to game settings
var game_settings: GameSettings = null

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
		"base_weight": 0.1,
		"is_currency": false
	},
	ResourceType.METAL_ORE: {
		"name": "Metal Ore",
		"description": "Raw metal ore from asteroid mining",
		"icon": null,
		"base_value": 10.0,
		"base_weight": 2.0,
		"is_currency": false
	},
	ResourceType.PRECIOUS_METALS: {
		"name": "Precious Metals",
		"description": "High-value refined metals",
		"icon": null,
		"base_value": 50.0,
		"base_weight": 1.0,
		"is_currency": false
	},
	ResourceType.CRYSTALS: {
		"name": "Crystals",
		"description": "Rare crystals used in advanced technology",
		"icon": null,
		"base_value": 75.0,
		"base_weight": 0.5,
		"is_currency": false
	},
	ResourceType.ORGANIC_MATTER: {
		"name": "Organic Matter",
		"description": "Biological resources for various uses",
		"icon": null,
		"base_value": 15.0,
		"base_weight": 1.5,
		"is_currency": false
	},
	ResourceType.TECHNOLOGY_PARTS: {
		"name": "Technology Parts",
		"description": "Components for building advanced systems",
		"icon": null,
		"base_value": 40.0,
		"base_weight": 0.8,
		"is_currency": false
	},
	ResourceType.WEAPONS_COMPONENTS: {
		"name": "Weapons Components",
		"description": "Parts for manufacturing weapons",
		"icon": null,
		"base_value": 60.0,
		"base_weight": 1.2,
		"is_currency": false
	},
	ResourceType.MEDICAL_SUPPLIES: {
		"name": "Medical Supplies",
		"description": "Essential medical equipment and medicines",
		"icon": null,
		"base_value": 35.0,
		"base_weight": 0.7,
		"is_currency": false
	},
	ResourceType.LUXURY_GOODS: {
		"name": "Luxury Goods",
		"description": "High-value luxury items",
		"icon": null,
		"base_value": 100.0,
		"base_weight": 0.3,
		"is_currency": false
	}
}

# Inventory and capacity
var inventory: Dictionary = {}  # resource_id -> amount
var cargo_capacity: float = 100.0
var used_capacity: float = 0.0

# Market price fluctuations for different stations/regions
var market_modifiers: Dictionary = {}  # station_id -> { resource_id -> price_modifier }

# Seed-related variables
var _seed_ready: bool = false
var debug_mode: bool = false

func _ready() -> void:
	# Initialize inventory with zero amounts
	for resource_id in resource_data:
		inventory[resource_id] = 0.0
	
	# Check SeedManager dependency
	_seed_ready = has_node("/root/SeedManager")
	
	# Look for GameSettings in the main scene
	call_deferred("_find_game_settings")

func _find_game_settings() -> void:
	# Wait a frame to ensure the scene is loaded
	await get_tree().process_frame
	
	# Find GameSettings in the main scene
	var main_scene = get_tree().current_scene
	game_settings = main_scene.get_node_or_null("GameSettings")
	
	if game_settings:
		debug_mode = game_settings.debug_mode
		if debug_mode:
			print("ResourceManager: Connected to GameSettings")
		
		# Listen for seed changes if SeedManager is available
		if _seed_ready and has_node("/root/SeedManager"):
			if SeedManager.has_signal("seed_changed") and not SeedManager.is_connected("seed_changed", _on_seed_changed):
				SeedManager.connect("seed_changed", _on_seed_changed)

# Handle seed changes
func _on_seed_changed(new_seed: int) -> void:
	if debug_mode:
		print("ResourceManager: Detected seed change to ", new_seed)
	
	# You might want to update market modifiers or other procedural values here
	_update_market_modifiers()

# Add resources to inventory
func add_resource(resource_id: int, amount: float) -> bool:
	if amount <= 0:
		return false
	
	var old_amount = inventory[resource_id]
	
	# Check cargo capacity for non-currency resources
	if not resource_data[resource_id]["is_currency"]:
		var weight_per_unit = resource_data[resource_id]["base_weight"]
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
	if not resource_data[resource_id]["is_currency"]:
		var weight_per_unit = resource_data[resource_id]["base_weight"]
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
	if resource_data[resource_id]["is_currency"]:
		return true  # Currency doesn't take cargo space
	
	var weight_per_unit = resource_data[resource_id]["base_weight"]
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
			total_value += inventory[resource_id] * resource_data[resource_id]["base_value"]
	
	return total_value

# Get the resource name
func get_resource_name(resource_id: int) -> String:
	if resource_data.has(resource_id):
		return resource_data[resource_id]["name"]
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
		if not resource_data[resource_id]["is_currency"]:
			required_capacity += buy_resources[resource_id] * resource_data[resource_id]["base_weight"]
	
	var freed_capacity = 0.0
	for resource_id in sell_resources:
		if not resource_data[resource_id]["is_currency"]:
			freed_capacity += sell_resources[resource_id] * resource_data[resource_id]["base_weight"]
	
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
	
	# Notify any event system
	if has_node("/root/EventManager"):
		EventManager.safe_emit("trade_completed", [station_id, buy_resources, sell_resources, credits_change])
	
	return true

# Set market price modifiers for a station
func set_station_market_modifiers(station_id: String, modifiers: Dictionary) -> void:
	market_modifiers[station_id] = modifiers

# Get the price of a resource at a specific station
func get_resource_price(resource_id: int, station_id: String = "") -> float:
	var base_price = resource_data[resource_id]["base_value"]
	
	if station_id.is_empty() or not market_modifiers.has(station_id):
		return base_price
	
	var station_modifiers = market_modifiers[station_id]
	
	if not station_modifiers.has(resource_id):
		return base_price
	
	return base_price * station_modifiers[resource_id]

# Reset all resources to zero
func reset_resources() -> void:
	for resource_id in inventory:
		var old_amount = inventory[resource_id]
		inventory[resource_id] = 0.0
		resource_changed.emit(resource_id, 0.0, old_amount)
	
	used_capacity = 0.0

# Initialize with starting resources from GameSettings
func initialize_starting_resources() -> void:
	# Reset first
	reset_resources()
	
	if game_settings:
		# Set up starting resources based on settings
		add_resource(ResourceType.CREDITS, game_settings.player_starting_credits)
		add_resource(ResourceType.FUEL, game_settings.player_starting_fuel)
		
		if debug_mode:
			print("ResourceManager: Initialized with starting credits: ", 
				  game_settings.player_starting_credits, 
				  ", fuel: ", game_settings.player_starting_fuel)
	else:
		# Fallback to default starting values
		add_resource(ResourceType.CREDITS, 1000)
		add_resource(ResourceType.FUEL, 100)

# Generate deterministic market modifiers based on seed
func _update_market_modifiers() -> void:
	# Clear existing modifiers
	market_modifiers.clear()
	
	# Only proceed if SeedManager is available
	if not _seed_ready or not has_node("/root/SeedManager"):
		return
	
	# Get the current seed
	var current_seed = SeedManager.get_seed()
	
	# Define stations - in a real implementation, these would come from a 
	# world generator or station manager
	var station_ids = ["station_1", "station_2", "station_3", "station_4"]
	
	# For each station, generate deterministic price modifiers
	for i in range(station_ids.size()):
		var station_id = station_ids[i]
		var station_modifiers = {}
		
		# For each resource type, generate a modifier
		for resource_id in resource_data:
			if resource_id == ResourceType.CREDITS:
				continue  # Skip credits
			
			# Create a deterministic object ID for this station-resource combination
			var object_id = hash(station_id) + resource_id * 100
			
			# Generate a price modifier between 0.7 and 1.3
			var price_modifier = SeedManager.get_random_value(object_id, 0.7, 1.3)
			
			# Some resources might be completely unavailable (null) or in high demand
			var availability_roll = SeedManager.get_random_value(object_id, 0.0, 1.0, 1)
			
			if availability_roll < 0.1:
				# Resource is unavailable
				price_modifier = 0.0
			elif availability_roll > 0.9:
				# Resource is in high demand
				price_modifier *= 1.5
			
			station_modifiers[resource_id] = price_modifier
		
		# Set the modifiers for this station
		market_modifiers[station_id] = station_modifiers
	
	if debug_mode:
		print("ResourceManager: Updated market modifiers using seed ", current_seed)
		
		# Print first station modifiers as an example
		if not station_ids.is_empty():
			var sample_station = station_ids[0]
			print("Sample modifiers for ", sample_station, ":")
			for resource_id in market_modifiers[sample_station]:
				var modifier = market_modifiers[sample_station][resource_id]
				print("  ", get_resource_name(resource_id), ": ", modifier)
