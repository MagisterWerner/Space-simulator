extends Node

signal resource_added(resource_id, amount)
signal resource_removed(resource_id, amount)
signal resource_changed(resource_id, new_amount, old_amount)
signal cargo_capacity_changed(new_capacity, old_capacity)

var game_settings = null

# Resource types enum
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

# Resource indices for array format
enum ResourceIndex {
	NAME,
	DESC,
	ICON,
	VALUE,
	WEIGHT,
	IS_CURRENCY
}

# Resource metadata - optimized as arrays
var resource_data = {
	ResourceType.CREDITS: ["Credits", "Universal currency", null, 1.0, 0.0, true],
	ResourceType.FUEL: ["Fuel", "Standard ship fuel", null, 5.0, 0.1, false],
	ResourceType.METAL_ORE: ["Metal Ore", "Raw metal ore", null, 10.0, 2.0, false],
	ResourceType.PRECIOUS_METALS: ["Precious Metals", "High-value metals", null, 50.0, 1.0, false],
	ResourceType.CRYSTALS: ["Crystals", "Rare crystals", null, 75.0, 0.5, false],
	ResourceType.ORGANIC_MATTER: ["Organic Matter", "Biological resources", null, 15.0, 1.5, false],
	ResourceType.TECHNOLOGY_PARTS: ["Technology Parts", "Tech components", null, 40.0, 0.8, false],
	ResourceType.WEAPONS_COMPONENTS: ["Weapons Components", "Weapon parts", null, 60.0, 1.2, false],
	ResourceType.MEDICAL_SUPPLIES: ["Medical Supplies", "Medical items", null, 35.0, 0.7, false],
	ResourceType.LUXURY_GOODS: ["Luxury Goods", "High-value items", null, 100.0, 0.3, false]
}

# Inventory and capacity
var inventory = {}
var cargo_capacity = 100.0
var used_capacity = 0.0

# Market price fluctuations
var market_modifiers = {}
var _seed_ready = false
var debug_mode = false

func _ready() -> void:
	# Initialize inventory with zero amounts
	for resource_id in ResourceType.values():
		inventory[resource_id] = 0.0
	
	_seed_ready = has_node("/root/SeedManager")
	call_deferred("_find_game_settings")

func _find_game_settings() -> void:
	await get_tree().process_frame
	
	var main_scene = get_tree().current_scene
	game_settings = main_scene.get_node_or_null("GameSettings")
	
	if game_settings:
		debug_mode = game_settings.debug_mode
		
		# Connect to SeedManager
		if _seed_ready and has_node("/root/SeedManager"):
			if SeedManager.has_signal("seed_changed") and not SeedManager.is_connected("seed_changed", _on_seed_changed):
				SeedManager.connect("seed_changed", _on_seed_changed)

# Fixed: Added parameter name with underscore to indicate it's intentionally unused
func _on_seed_changed(_new_seed: int) -> void:
	_update_market_modifiers()

# Add resources to inventory
func add_resource(resource_id, amount) -> bool:
	if amount <= 0:
		return false
	
	var old_amount = inventory[resource_id]
	
	# Check cargo capacity for non-currency resources
	if not resource_data[resource_id][ResourceIndex.IS_CURRENCY]:
		var weight_per_unit = resource_data[resource_id][ResourceIndex.WEIGHT]
		var additional_weight = amount * weight_per_unit
		
		if used_capacity + additional_weight > cargo_capacity:
			return false
		
		used_capacity += additional_weight
	
	# Add the resource
	inventory[resource_id] += amount
	
	# Emit signals
	resource_added.emit(resource_id, amount)
	resource_changed.emit(resource_id, inventory[resource_id], old_amount)
	
	return true

# Remove resources from inventory
func remove_resource(resource_id, amount) -> bool:
	if amount <= 0 or inventory[resource_id] < amount:
		return false
	
	var old_amount = inventory[resource_id]
	
	# Remove the resource
	inventory[resource_id] -= amount
	
	# Update used capacity
	if not resource_data[resource_id][ResourceIndex.IS_CURRENCY]:
		var weight_per_unit = resource_data[resource_id][ResourceIndex.WEIGHT]
		var reduced_weight = amount * weight_per_unit
		used_capacity -= reduced_weight
	
	# Emit signals
	resource_removed.emit(resource_id, amount)
	resource_changed.emit(resource_id, inventory[resource_id], old_amount)
	
	return true

# Set cargo capacity
func set_cargo_capacity(new_capacity) -> void:
	if new_capacity == cargo_capacity:
		return
	
	var old_capacity = cargo_capacity
	cargo_capacity = max(0.0, new_capacity)
	
	cargo_capacity_changed.emit(cargo_capacity, old_capacity)

# Get available cargo space
func get_available_cargo_space() -> float:
	return cargo_capacity - used_capacity

# Check if there's enough cargo space for a resource amount
func has_cargo_space_for(resource_id, amount) -> bool:
	if resource_data[resource_id][ResourceIndex.IS_CURRENCY]:
		return true
	
	var weight_per_unit = resource_data[resource_id][ResourceIndex.WEIGHT]
	var required_space = amount * weight_per_unit
	
	return get_available_cargo_space() >= required_space

# Get the current amount of a resource
func get_resource_amount(resource_id) -> float:
	return inventory[resource_id]

# Check if the player has enough of a resource
func has_resource(resource_id, amount) -> bool:
	return inventory[resource_id] >= amount

# Get the total value of cargo (excluding credits)
func get_total_cargo_value() -> float:
	var total_value = 0.0
	
	for resource_id in inventory:
		if resource_id != ResourceType.CREDITS:
			total_value += inventory[resource_id] * resource_data[resource_id][ResourceIndex.VALUE]
	
	return total_value

# Get the resource name
func get_resource_name(resource_id) -> String:
	if resource_data.has(resource_id):
		return resource_data[resource_id][ResourceIndex.NAME]
	return "Unknown Resource"

# Trade resources with a station
func trade_with_station(station_id, buy_resources, sell_resources) -> bool:
	# Calculate costs and earnings
	var total_cost = 0.0
	var total_earnings = 0.0
	
	for resource_id in buy_resources:
		var amount = buy_resources[resource_id]
		var price_per_unit = get_resource_price(resource_id, station_id)
		total_cost += amount * price_per_unit
	
	for resource_id in sell_resources:
		var amount = sell_resources[resource_id]
		var price_per_unit = get_resource_price(resource_id, station_id)
		total_earnings += amount * price_per_unit
	
	# Check if player has enough credits
	if total_cost > inventory[ResourceType.CREDITS]:
		return false
	
	# Check if player has the resources to sell
	for resource_id in sell_resources:
		if not has_resource(resource_id, sell_resources[resource_id]):
			return false
	
	# Check cargo capacity
	var required_capacity = 0.0
	var freed_capacity = 0.0
	
	for resource_id in buy_resources:
		if not resource_data[resource_id][ResourceIndex.IS_CURRENCY]:
			required_capacity += buy_resources[resource_id] * resource_data[resource_id][ResourceIndex.WEIGHT]
	
	for resource_id in sell_resources:
		if not resource_data[resource_id][ResourceIndex.IS_CURRENCY]:
			freed_capacity += sell_resources[resource_id] * resource_data[resource_id][ResourceIndex.WEIGHT]
	
	if get_available_cargo_space() + freed_capacity < required_capacity:
		return false
	
	# Execute the trade
	var credits_change = total_earnings - total_cost
	
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
	
	# Notify event system
	if has_node("/root/EventManager"):
		EventManager.safe_emit("trade_completed", [station_id, buy_resources, sell_resources, credits_change])
	
	return true

# Set market price modifiers for a station
func set_station_market_modifiers(station_id, modifiers) -> void:
	market_modifiers[station_id] = modifiers

# Get the price of a resource at a specific station
func get_resource_price(resource_id, station_id = "") -> float:
	var base_price = resource_data[resource_id][ResourceIndex.VALUE]
	
	if station_id.is_empty() or not market_modifiers.has(station_id):
		return base_price
	
	var station_modifiers = market_modifiers[station_id]
	
	if not station_modifiers.has(resource_id):
		return base_price
	
	return base_price * station_modifiers[resource_id]

# Reset all resources
func reset_resources() -> void:
	for resource_id in inventory:
		var old_amount = inventory[resource_id]
		inventory[resource_id] = 0.0
		resource_changed.emit(resource_id, 0.0, old_amount)
	
	used_capacity = 0.0

# Initialize with starting resources
func initialize_starting_resources() -> void:
	reset_resources()
	
	if game_settings:
		add_resource(ResourceType.CREDITS, game_settings.player_starting_credits)
		add_resource(ResourceType.FUEL, game_settings.player_starting_fuel)
	else:
		add_resource(ResourceType.CREDITS, 1000)
		add_resource(ResourceType.FUEL, 100)

# Generate deterministic market modifiers
func _update_market_modifiers() -> void:
	market_modifiers.clear()
	
	if not _seed_ready or not has_node("/root/SeedManager"):
		return
	
	# Fixed: Renamed to _current_seed to indicate it's intentionally used
	var _current_seed = SeedManager.get_seed()
	var station_ids = ["station_1", "station_2", "station_3", "station_4"]
	
	for i in range(station_ids.size()):
		var station_id = station_ids[i]
		var station_modifiers = {}
		
		for resource_id in resource_data:
			if resource_id == ResourceType.CREDITS:
				continue
			
			var object_id = hash(station_id) + resource_id * 100
			
			# Generate price modifier
			var price_modifier = SeedManager.get_random_value(object_id, 0.7, 1.3)
			
			# Resource availability
			var availability_roll = SeedManager.get_random_value(object_id, 0.0, 1.0, 1)
			
			if availability_roll < 0.1:
				price_modifier = 0.0  # Unavailable
			elif availability_roll > 0.9:
				price_modifier *= 1.5  # High demand
			
			station_modifiers[resource_id] = price_modifier
		
		market_modifiers[station_id] = station_modifiers
