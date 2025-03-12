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

# Resource class for better data organization
class ResourceData:
	var name: String
	var description: String
	var icon: Texture2D
	var base_value: float
	var weight: float
	var is_currency: bool
	
	func _init(p_name: String, p_desc: String, p_icon = null, p_value: float = 0.0, p_weight: float = 0.0, p_is_currency: bool = false):
		name = p_name
		description = p_desc
		icon = p_icon
		base_value = p_value
		weight = p_weight
		is_currency = p_is_currency

# Resource data storage - optimized with class instances
var resource_data = {}

# Inventory and capacity
var inventory = {}
var cargo_capacity: float = 100.0
var used_capacity: float = 0.0

# Market price caching
var market_modifiers = {}
var market_prices_cache = {}
var _seed_manager = null
var _debug_mode = false

func _ready() -> void:
	_initialize_resource_data()
	_initialize_inventory()
	_connect_to_seed_manager()
	call_deferred("_find_game_settings")

func _initialize_resource_data() -> void:
	# Define all resources using the ResourceData class
	resource_data[ResourceType.CREDITS] = ResourceData.new("Credits", "Universal currency", null, 1.0, 0.0, true)
	resource_data[ResourceType.FUEL] = ResourceData.new("Fuel", "Standard ship fuel", null, 5.0, 0.1, false)
	resource_data[ResourceType.METAL_ORE] = ResourceData.new("Metal Ore", "Raw metal ore", null, 10.0, 2.0, false)
	resource_data[ResourceType.PRECIOUS_METALS] = ResourceData.new("Precious Metals", "High-value metals", null, 50.0, 1.0, false)
	resource_data[ResourceType.CRYSTALS] = ResourceData.new("Crystals", "Rare crystals", null, 75.0, 0.5, false)
	resource_data[ResourceType.ORGANIC_MATTER] = ResourceData.new("Organic Matter", "Biological resources", null, 15.0, 1.5, false)
	resource_data[ResourceType.TECHNOLOGY_PARTS] = ResourceData.new("Technology Parts", "Tech components", null, 40.0, 0.8, false)
	resource_data[ResourceType.WEAPONS_COMPONENTS] = ResourceData.new("Weapons Components", "Weapon parts", null, 60.0, 1.2, false)
	resource_data[ResourceType.MEDICAL_SUPPLIES] = ResourceData.new("Medical Supplies", "Medical items", null, 35.0, 0.7, false)
	resource_data[ResourceType.LUXURY_GOODS] = ResourceData.new("Luxury Goods", "High-value items", null, 100.0, 0.3, false)

func _initialize_inventory() -> void:
	# Initialize all resource amounts to zero
	for resource_id in ResourceType.values():
		inventory[resource_id] = 0.0

func _connect_to_seed_manager() -> void:
	if Engine.has_singleton("SeedManager"):
		_seed_manager = Engine.get_singleton("SeedManager")
		
		# Connect to seed changes for market updates
		if _seed_manager.has_signal("seed_changed") and not _seed_manager.is_connected("seed_changed", _on_seed_changed):
			_seed_manager.connect("seed_changed", _on_seed_changed)
		
		# Wait for initialization if needed
		if _seed_manager.has_method("is_initialized") and not _seed_manager.is_initialized:
			if _seed_manager.has_signal("seed_initialized"):
				_seed_manager.seed_initialized.connect(_on_seed_manager_initialized)

func _on_seed_manager_initialized() -> void:
	_update_market_modifiers()

func _on_seed_changed(_new_seed) -> void:
	_update_market_modifiers()
	market_prices_cache.clear()

func _find_game_settings() -> void:
	# Find game settings reference
	var main_scene = get_tree().current_scene
	game_settings = main_scene.get_node_or_null("GameSettings")
	
	if game_settings:
		_debug_mode = game_settings.debug_mode
		
		# Connect to debug settings changes
		if game_settings.has_signal("debug_settings_changed") and not game_settings.is_connected("debug_settings_changed", _on_debug_settings_changed):
			game_settings.connect("debug_settings_changed", _on_debug_settings_changed)

func _on_debug_settings_changed(debug_settings: Dictionary) -> void:
	_debug_mode = debug_settings.get("master", false)

# Add resources to inventory - optimized with early returns and direct property access
func add_resource(resource_id, amount) -> bool:
	if amount <= 0:
		return false
	
	var old_amount = inventory[resource_id]
	var res_data = resource_data[resource_id]
	
	# Check cargo capacity for non-currency resources
	if not res_data.is_currency:
		var additional_weight = amount * res_data.weight
		
		if used_capacity + additional_weight > cargo_capacity:
			return false
		
		used_capacity += additional_weight
	
	# Add the resource
	inventory[resource_id] += amount
	
	# Emit signals
	resource_added.emit(resource_id, amount)
	resource_changed.emit(resource_id, inventory[resource_id], old_amount)
	
	return true

# Remove resources from inventory - optimized with early returns
func remove_resource(resource_id, amount) -> bool:
	if amount <= 0 or inventory[resource_id] < amount:
		return false
	
	var old_amount = inventory[resource_id]
	var res_data = resource_data[resource_id]
	
	# Remove the resource
	inventory[resource_id] -= amount
	
	# Update used capacity
	if not res_data.is_currency:
		var reduced_weight = amount * res_data.weight
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
	var res_data = resource_data[resource_id]
	
	if res_data.is_currency:
		return true
	
	var required_space = amount * res_data.weight
	return get_available_cargo_space() >= required_space

# Get the current amount of a resource
func get_resource_amount(resource_id) -> float:
	return inventory[resource_id]

# Check if the player has enough of a resource
func has_resource(resource_id, amount) -> bool:
	return inventory[resource_id] >= amount

# Get the total value of cargo (excluding credits) - optimized with fewer lookup operations
func get_total_cargo_value() -> float:
	var total_value = 0.0
	
	for resource_id in inventory:
		if resource_id != ResourceType.CREDITS:
			var amount = inventory[resource_id]
			if amount > 0:
				total_value += amount * resource_data[resource_id].base_value
	
	return total_value

# Get the resource name
func get_resource_name(resource_id) -> String:
	if resource_data.has(resource_id):
		return resource_data[resource_id].name
	return "Unknown Resource"

# Trade resources with a station - optimized trade validation
func trade_with_station(station_id, buy_resources, sell_resources) -> bool:
	# Calculate costs and validate resources in one pass
	var total_cost = 0.0
	var total_earnings = 0.0
	var required_capacity = 0.0
	var freed_capacity = 0.0
	
	# Validate sell resources and calculate freed capacity
	for resource_id in sell_resources:
		var amount = sell_resources[resource_id]
		
		# Check if player has this resource
		if not has_resource(resource_id, amount):
			return false
			
		# Calculate freed capacity and earnings
		var res_data = resource_data[resource_id]
		if not res_data.is_currency:
			freed_capacity += amount * res_data.weight
		
		var price = get_resource_price(resource_id, station_id)
		total_earnings += amount * price
	
	# Validate buy resources and calculate required capacity
	for resource_id in buy_resources:
		var amount = buy_resources[resource_id]
		var res_data = resource_data[resource_id]
		
		if not res_data.is_currency:
			required_capacity += amount * res_data.weight
		
		var price = get_resource_price(resource_id, station_id)
		total_cost += amount * price
	
	# Check if player has enough credits
	if total_cost > inventory[ResourceType.CREDITS] + total_earnings:
		return false
	
	# Check cargo capacity
	if get_available_cargo_space() + freed_capacity < required_capacity:
		return false
	
	# Execute the trade
	var credits_change = total_earnings - total_cost
	
	# Handle credits change
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
	
	# Clear cached prices
	market_prices_cache.clear()
	
	return true

# Set market price modifiers for a station
func set_station_market_modifiers(station_id, modifiers) -> void:
	market_modifiers[station_id] = modifiers
	
	# Clear cached prices for this station
	var station_cache_key = "station_" + str(station_id)
	for key in market_prices_cache.keys():
		if key.begins_with(station_cache_key):
			market_prices_cache.erase(key)

# Get the price of a resource at a specific station - with caching
func get_resource_price(resource_id, station_id = "") -> float:
	# Use cache if available
	var cache_key = "station_" + str(station_id) + "_resource_" + str(resource_id)
	if market_prices_cache.has(cache_key):
		return market_prices_cache[cache_key]
		
	var base_price = resource_data[resource_id].base_value
	
	if station_id.is_empty() or not market_modifiers.has(station_id):
		market_prices_cache[cache_key] = base_price
		return base_price
	
	var station_modifiers = market_modifiers[station_id]
	
	if not station_modifiers.has(resource_id):
		market_prices_cache[cache_key] = base_price
		return base_price
	
	var price = base_price * station_modifiers[resource_id]
	market_prices_cache[cache_key] = price
	return price

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

# Generate deterministic market modifiers - fully integrated with SeedManager
func _update_market_modifiers() -> void:
	market_modifiers.clear()
	market_prices_cache.clear()
	
	if not _seed_manager:
		return
	
	var station_ids = ["station_1", "station_2", "station_3", "station_4"]
	
	for i in range(station_ids.size()):
		var station_id = station_ids[i]
		var station_modifiers = {}
		
		for resource_id in resource_data:
			if resource_id == ResourceType.CREDITS:
				continue
			
			# Generate deterministic object ID
			var object_id = hash(station_id) + resource_id * 100
			
			# Get price modifier from SeedManager
			var price_modifier = _seed_manager.get_random_value(object_id, 0.7, 1.3)
			
			# Resource availability
			var availability_roll = _seed_manager.get_random_value(object_id, 0.0, 1.0, 1)
			
			if availability_roll < 0.1:
				price_modifier = 0.0  # Unavailable
			elif availability_roll > 0.9:
				price_modifier *= 1.5  # High demand
			
			station_modifiers[resource_id] = price_modifier
		
		market_modifiers[station_id] = station_modifiers
	
	if _debug_mode:
		print("ResourceManager: Updated market modifiers with current seed")
