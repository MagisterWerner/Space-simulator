# autoload/game_manager.gd
# Game Manager refactored with dependency injection
# Handles game lifecycle, player state, upgrades, and game persistence

extends "res://autoload/base_service.gd"

signal game_started
signal game_paused
signal game_resumed
signal game_over
signal game_restarted
signal player_credits_changed(new_amount)
signal upgrade_purchased(upgrade, component)
signal save_game_created(save_id)
signal save_game_loaded(save_id)

# Game state
var game_running: bool = false
var is_game_paused: bool = false
var current_level: String = ""
var player_ship = null
var game_settings = null

# Start position override from Main.gd
var player_start_position: Vector2 = Vector2.ZERO
var player_start_cell: Vector2i = Vector2i(-1, -1)
var use_custom_start_position: bool = false

# Upgrade system
var available_upgrades: Array = []
var player_upgrades: Array = []

# Service references
var entity_manager = null
var resource_manager = null
var event_manager = null
var seed_manager = null

func _ready() -> void:
	# Wait one frame before registering to ensure ServiceLocator is ready
	await get_tree().process_frame
	register_self()
	
	# Set process mode to continue during pause
	process_mode = Node.PROCESS_MODE_ALWAYS

# Return dependencies required by this service
func get_dependencies() -> Array:
	return ["EntityManager", "ResourceManager", "EventManager", "SeedManager"]

# Initialize this service
func initialize_service() -> void:
	# Get dependencies from ServiceLocator with proper error handling
	seed_manager = get_dependency("SeedManager")
	if not seed_manager:
		push_error("GameManager: Failed to get SeedManager dependency")
	
	entity_manager = get_dependency("EntityManager")
	if not entity_manager:
		push_error("GameManager: Failed to get EntityManager dependency")
	
	resource_manager = get_dependency("ResourceManager")
	if not resource_manager:
		push_error("GameManager: Failed to get ResourceManager dependency")
	
	event_manager = get_dependency("EventManager")
	if not event_manager:
		push_error("GameManager: Failed to get EventManager dependency")
	
	# Get optional GameSettings dependency
	if has_dependency("GameSettings"):
		game_settings = get_dependency("GameSettings")
		
		# Configure with GameSettings
		if game_settings and game_settings.has_method("get_seed") and seed_manager:
			seed_manager.set_seed(game_settings.get_seed())
			
			# Connect to seed changes
			connect_to_dependency("GameSettings", "seed_changed", _on_settings_seed_changed)
	
	# Connect to event signals
	_connect_event_signals()
	
	# Connect to resource signals
	_connect_resource_signals()
	
	# Initialize entity scenes
	_initialize_entity_scenes()
	
	# Initialize available upgrades
	_initialize_available_upgrades()
	
	# Mark as initialized
	_service_initialized = true
	print("GameManager: Service initialized successfully")

func _connect_event_signals() -> void:
	# Connect to EventManager signals
	if event_manager:
		# A safer way to connect signals with error checking
		var signals_to_connect = {
			"credits_changed": _on_player_credits_changed,
			"player_died": _on_player_died,
		}
		
		for signal_name in signals_to_connect:
			if event_manager.has_signal(signal_name):
				if not event_manager.is_connected(signal_name, signals_to_connect[signal_name]):
					event_manager.connect(signal_name, signals_to_connect[signal_name])
			else:
				push_warning("GameManager: EventManager is missing signal: " + signal_name)

func _connect_resource_signals() -> void:
	# Connect to ResourceManager signals
	if resource_manager and resource_manager.has_signal("resource_changed"):
		if not resource_manager.is_connected("resource_changed", _on_resource_changed):
			resource_manager.resource_changed.connect(_on_resource_changed)

func _initialize_entity_scenes() -> void:
	# Initialize entity scenes in EntityManager
	if entity_manager and entity_manager.has_method("_initialize_scenes"):
		if not entity_manager._scenes_initialized:
			entity_manager._initialize_scenes()

# Handle seed changes from settings
func _on_settings_seed_changed(new_seed: int) -> void:
	# Update SeedManager with new seed
	if seed_manager:
		seed_manager.set_seed(new_seed)

# Set the player's start position from Main.gd
func set_player_start_position(position: Vector2, cell: Vector2i = Vector2i(-1, -1)) -> void:
	player_start_position = position
	player_start_cell = cell
	use_custom_start_position = true
	
	if game_settings and "debug_mode" in game_settings and game_settings.debug_mode:
		print("GameManager: Player start position set to ", position, " (cell: ", cell, ")")

# Game lifecycle methods
func start_game() -> void:
	if game_running:
		return
	
	# Reset game state
	game_running = true
	is_game_paused = false
	player_upgrades.clear()
	
	# Ensure SeedManager has the correct seed before world generation
	if seed_manager and game_settings and game_settings.has_method("get_seed"):
		seed_manager.set_seed(game_settings.get_seed())
	
	# Determine spawn position
	var spawn_position = Vector2.ZERO
	
	# First priority: Use custom start position if available
	if use_custom_start_position and player_start_position != Vector2.ZERO:
		spawn_position = player_start_position
	# Second priority: Use GameSettings
	elif game_settings and game_settings.has_method("get_player_starting_position"):
		spawn_position = game_settings.get_player_starting_position()
	# Last resort: Use viewport center
	else:
		var viewport_size = get_viewport().get_visible_rect().size
		spawn_position = viewport_size / 2
	
	# Spawn the player at the determined position
	if entity_manager:
		player_ship = entity_manager.spawn_player(spawn_position)
		if player_ship and game_settings and "debug_mode" in game_settings and game_settings.debug_mode:
			print("GameManager: Spawned player at position: ", spawn_position)
	else:
		push_error("GameManager: Cannot spawn player - EntityManager not available")
		return
	
	# Initialize resources
	if resource_manager:
		# Clear inventory
		for resource_id in resource_manager.resource_data:
			resource_manager.inventory[resource_id] = 0
		
		# Set starting resources from GameSettings if available
		if game_settings:
			if "player_starting_credits" in game_settings:
				resource_manager.add_resource(resource_manager.ResourceType.CREDITS, game_settings.player_starting_credits)
			if "player_starting_fuel" in game_settings:
				resource_manager.add_resource(resource_manager.ResourceType.FUEL, game_settings.player_starting_fuel)
		else:
			# Default starting resources
			resource_manager.add_resource(resource_manager.ResourceType.CREDITS, 1000)
			resource_manager.add_resource(resource_manager.ResourceType.FUEL, 100)
	
	# Emit game started signal
	game_started.emit()
	if event_manager:
		event_manager.safe_emit("game_started")
	
	print("GameManager: Game started successfully")

func pause_game() -> void:
	if not game_running or is_game_paused:
		return
	
	# Pause the game
	is_game_paused = true
	get_tree().paused = true
	
	# Emit game paused signal
	game_paused.emit()
	if event_manager:
		event_manager.safe_emit("game_paused")

func resume_game() -> void:
	if not game_running or not is_game_paused:
		return
	
	# Resume the game
	is_game_paused = false
	get_tree().paused = false
	
	# Emit game resumed signal
	game_resumed.emit()
	if event_manager:
		event_manager.safe_emit("game_resumed")

func end_game() -> void:
	if not game_running:
		return
	
	# End the game
	game_running = false
	is_game_paused = false
	get_tree().paused = false
	
	# Emit game over signal
	game_over.emit()
	if event_manager:
		event_manager.safe_emit("game_over")

func restart_game() -> void:
	# End the current game
	if game_running:
		end_game()
	
	# Clear all entities
	if entity_manager:
		entity_manager.despawn_all()
	
	# Start a new game
	start_game()
	
	# Emit game restarted signal
	game_restarted.emit()
	if event_manager:
		event_manager.safe_emit("game_restarted")

# Event handlers
func _on_player_spawned(player) -> void:
	player_ship = player
	
	# Connect player signals
	if player_ship and is_instance_valid(player_ship):
		if player_ship.has_signal("player_died") and not player_ship.player_died.is_connected(_on_player_died):
			player_ship.player_died.connect(_on_player_died)

func _on_player_died() -> void:
	# Handle player death
	# Could trigger game over or respawn after delay
	await get_tree().create_timer(3.0).timeout
	
	if player_ship and is_instance_valid(player_ship):
		# Respawn the player
		var respawn_position
		
		if use_custom_start_position and player_start_position != Vector2.ZERO:
			respawn_position = player_start_position
		elif game_settings and game_settings.has_method("get_player_starting_position"):
			respawn_position = game_settings.get_player_starting_position()
		else:
			var viewport_size = get_viewport().get_visible_rect().size
			respawn_position = viewport_size / 2
			
		if player_ship.has_method("respawn"):
			player_ship.respawn(respawn_position)
		else:
			# If player ship doesn't have respawn method, we need to create a new one
			if entity_manager:
				entity_manager.despawn_all("player")
				player_ship = entity_manager.spawn_player(respawn_position)
	else:
		# End the game if player is no longer valid
		end_game()

func _on_player_earned_credits(amount: float) -> void:
	if resource_manager:
		resource_manager.add_resource(resource_manager.ResourceType.CREDITS, amount)

func _on_player_spent_credits(amount: float) -> void:
	if resource_manager:
		resource_manager.remove_resource(resource_manager.ResourceType.CREDITS, amount)

func _on_player_credits_changed(new_amount: float) -> void:
	player_credits_changed.emit(new_amount)

func _on_resource_changed(resource_id: int, new_amount: float, _old_amount: float) -> void:
	# Handle resource changes
	if resource_manager and resource_id == resource_manager.ResourceType.CREDITS:
		player_credits_changed.emit(new_amount)
		if event_manager:
			event_manager.safe_emit("credits_changed", [new_amount])

# Upgrade system
func _initialize_available_upgrades() -> void:
	# First check if we have the necessary script resources loaded
	var weapon_strategies_script = load("res://scripts/strategies/weapon_strategies.gd")
	var shield_strategies_script = load("res://scripts/strategies/shield_strategies.gd")
	var movement_strategies_script = load("res://scripts/strategies/movement_strategies.gd")
	
	if not weapon_strategies_script or not shield_strategies_script or not movement_strategies_script:
		push_warning("Strategy scripts not found - skipping upgrade initialization")
		return
	
	# Create instances of weapon strategies
	if weapon_strategies_script:
		# We need to check if these classes exist on the script before instantiating them
		if "DoubleDamageStrategy" in weapon_strategies_script:
			var double_damage = weapon_strategies_script.DoubleDamageStrategy.new()
			available_upgrades.append(double_damage)
		
		if "RapidFireStrategy" in weapon_strategies_script:
			var rapid_fire = weapon_strategies_script.RapidFireStrategy.new()
			available_upgrades.append(rapid_fire)
		
		if "PiercingShotStrategy" in weapon_strategies_script:
			var piercing_shot = weapon_strategies_script.PiercingShotStrategy.new()
			available_upgrades.append(piercing_shot)
		
		if "SpreadShotStrategy" in weapon_strategies_script:
			var spread_shot = weapon_strategies_script.SpreadShotStrategy.new()
			available_upgrades.append(spread_shot)
	
	# Create instances of shield strategies
	if shield_strategies_script:
		if "ReinforcedShieldStrategy" in shield_strategies_script:
			var reinforced_shield = shield_strategies_script.ReinforcedShieldStrategy.new()
			available_upgrades.append(reinforced_shield)
		
		if "FastRechargeStrategy" in shield_strategies_script:
			var fast_recharge = shield_strategies_script.FastRechargeStrategy.new()
			available_upgrades.append(fast_recharge)
		
		if "ReflectiveShieldStrategy" in shield_strategies_script:
			var reflective_shield = shield_strategies_script.ReflectiveShieldStrategy.new()
			available_upgrades.append(reflective_shield)
		
		if "AbsorbentShieldStrategy" in shield_strategies_script:
			var absorbent_shield = shield_strategies_script.AbsorbentShieldStrategy.new()
			available_upgrades.append(absorbent_shield)
	
	# Create instances of movement strategies
	if movement_strategies_script:
		if "EnhancedThrustersStrategy" in movement_strategies_script:
			var enhanced_thrusters = movement_strategies_script.EnhancedThrustersStrategy.new()
			available_upgrades.append(enhanced_thrusters)
		
		if "ManeuverabilityStrategy" in movement_strategies_script:
			var maneuverability = movement_strategies_script.ManeuverabilityStrategy.new()
			available_upgrades.append(maneuverability)
		
		if "AfterburnerStrategy" in movement_strategies_script:
			var afterburner = movement_strategies_script.AfterburnerStrategy.new()
			available_upgrades.append(afterburner)
		
		if "InertialDampenersStrategy" in movement_strategies_script:
			var inertial_dampeners = movement_strategies_script.InertialDampenersStrategy.new()
			available_upgrades.append(inertial_dampeners)
	
	print("GameManager: Initialized %d available upgrades" % available_upgrades.size())

# Upgrade management
func purchase_upgrade(upgrade_index: int, component_name: String) -> bool:
	if upgrade_index < 0 or upgrade_index >= available_upgrades.size():
		return false
	
	var upgrade = available_upgrades[upgrade_index]
	
	# Check if upgrade has price property
	if not "price" in upgrade:
		push_warning("GameManager: Upgrade does not have a price property")
		return false
	
	# Check if player has enough credits
	if resource_manager and not resource_manager.has_resource(resource_manager.ResourceType.CREDITS, upgrade.price):
		return false
	
	# Apply the upgrade to the player ship
	if player_ship and is_instance_valid(player_ship):
		if player_ship.has_method("add_upgrade_strategy"):
			if player_ship.add_upgrade_strategy(upgrade, component_name):
				# Deduct credits
				if resource_manager:
					resource_manager.remove_resource(resource_manager.ResourceType.CREDITS, upgrade.price)
				
				# Add to player's upgrades
				player_upgrades.append({
					"upgrade": upgrade,
					"component": component_name
				})
				
				# Emit event
				upgrade_purchased.emit(upgrade, component_name)
				if event_manager:
					event_manager.safe_emit("upgrade_purchased", [upgrade, component_name, upgrade.price])
					if resource_manager:
						event_manager.safe_emit("credits_changed", [resource_manager.get_resource_amount(resource_manager.ResourceType.CREDITS)])
				
				return true
		else:
			push_warning("GameManager: Player ship doesn't have add_upgrade_strategy method")
	
	return false

func remove_upgrade(upgrade_index: int) -> bool:
	if upgrade_index < 0 or upgrade_index >= player_upgrades.size():
		return false
	
	var upgrade_info = player_upgrades[upgrade_index]
	
	if player_ship and is_instance_valid(player_ship):
		if player_ship.has_method("remove_upgrade_strategy"):
			player_ship.remove_upgrade_strategy(upgrade_info.upgrade)
			if event_manager:
				event_manager.safe_emit("upgrade_removed", [upgrade_info.upgrade, upgrade_info.component])
			player_upgrades.remove_at(upgrade_index)
			return true
		else:
			push_warning("GameManager: Player ship doesn't have remove_upgrade_strategy method")
	
	return false

func get_available_upgrades_for_component(component_name: String) -> Array:
	var filtered_upgrades = []
	
	for upgrade in available_upgrades:
		var upgrade_script = upgrade.get_script()
		if upgrade_script == null:
			continue
			
		var script_path = upgrade_script.resource_path
		
		# Filter based on component type and script path
		match component_name:
			"WeaponComponent":
				if "weapon_strategies" in script_path.to_lower():
					filtered_upgrades.append(upgrade)
			
			"ShieldComponent":
				if "shield_strategies" in script_path.to_lower():
					filtered_upgrades.append(upgrade)
			
			"MovementComponent":
				if "movement_strategies" in script_path.to_lower():
					filtered_upgrades.append(upgrade)
	
	return filtered_upgrades

# New save game functionality
func save_game(save_id: String = "") -> bool:
	if not game_running:
		return false
	
	# Generate save ID if not provided
	if save_id.is_empty():
		save_id = "save_" + Time.get_datetime_string_from_system().replace(":", "-")
	
	# Collect game state
	var save_data = {
		"version": "1.0",
		"timestamp": Time.get_unix_time_from_system(),
		"player": {
			"position": player_ship.global_position if player_ship else Vector2.ZERO,
			"upgrades": player_upgrades,
			# Add more player state here
		},
		"resources": resource_manager.inventory if resource_manager else {},
		"seed": game_settings.get_seed() if game_settings and game_settings.has_method("get_seed") else (seed_manager.get_seed() if seed_manager else 0),
		# Add more game state here
	}
	
	# Save to file
	var save_dir = "user://saves/"
	var save_path = save_dir + save_id + ".save"
	
	var dir = DirAccess.open("user://")
	if not dir.dir_exists(save_dir):
		dir.make_dir(save_dir)
	
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if not file:
		push_error("GameManager: Failed to save game - couldn't open file")
		return false
	
	file.store_var(save_data)
	file.close()
	
	save_game_created.emit(save_id)
	return true

func load_game(save_id: String) -> bool:
	var save_path = "user://saves/" + save_id + ".save"
	
	# Check if file exists
	if not FileAccess.file_exists(save_path):
		push_error("GameManager: Save file not found: " + save_path)
		return false
	
	# Load save data
	var file = FileAccess.open(save_path, FileAccess.READ)
	if not file:
		push_error("GameManager: Failed to load game - couldn't open file")
		return false
	
	var save_data = file.get_var()
	file.close()
	
	# Validate save data
	if not save_data is Dictionary or not save_data.has("version"):
		push_error("GameManager: Invalid save file format")
		return false
	
	# End current game if running
	if game_running:
		end_game()
	
	# Restore seed
	if save_data.has("seed"):
		if game_settings and game_settings.has_method("set_seed"):
			game_settings.set_seed(save_data.seed)
		elif seed_manager:
			seed_manager.set_seed(save_data.seed)
	
	# Start a new game
	start_game()
	
	# Restore player state
	if save_data.has("player") and player_ship:
		if save_data.player.has("position"):
			player_ship.global_position = save_data.player.position
		
		# Restore upgrades
		if save_data.player.has("upgrades"):
			player_upgrades = save_data.player.upgrades.duplicate()
			# Apply upgrades to player
			for upgrade_info in player_upgrades:
				if player_ship.has_method("add_upgrade_strategy"):
					player_ship.add_upgrade_strategy(upgrade_info.upgrade, upgrade_info.component)
	
	# Restore resources
	if resource_manager and save_data.has("resources"):
		for resource_id in save_data.resources:
			resource_manager.inventory[int(resource_id)] = save_data.resources[resource_id]
	
	save_game_loaded.emit(save_id)
	return true

# List all saved games
func get_saved_games() -> Array:
	var saved_games = []
	var save_dir = "user://saves/"
	
	var dir = DirAccess.open("user://")
	if not dir.dir_exists(save_dir):
		return saved_games
	
	dir = DirAccess.open(save_dir)
	if not dir:
		return saved_games
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".save"):
			var save_id = file_name.replace(".save", "")
			saved_games.append(save_id)
		file_name = dir.get_next()
	
	dir.list_dir_end()
	return saved_games

# Delete a saved game
func delete_saved_game(save_id: String) -> bool:
	var save_path = "user://saves/" + save_id + ".save"
	
	if not FileAccess.file_exists(save_path):
		return false
	
	var dir = DirAccess.open("user://saves/")
	if not dir:
		return false
	
	return dir.remove(save_path) == OK

# Input handling
func _input(event: InputEvent) -> void:
	# Handle game pause/resume input
	if event.is_action_pressed("pause"):
		if game_running:
			if is_game_paused:
				resume_game()
			else:
				pause_game()
	
	# Debug inputs
	if OS.is_debug_build():
		if event.is_action_pressed("debug_restart_game"):
			restart_game()
		elif event.is_action_pressed("debug_quit_game"):
			get_tree().quit()

# Utility methods
func get_game_time() -> float:
	return Time.get_ticks_msec() / 1000.0

func is_game_active() -> bool:
	return game_running and not is_game_paused

# Get player position, with fallback if player doesn't exist
func get_player_position() -> Vector2:
	if player_ship and is_instance_valid(player_ship):
		return player_ship.global_position
	
	# Fallback
	if use_custom_start_position:
		return player_start_position
	elif game_settings and game_settings.has_method("get_player_starting_position"):
		return game_settings.get_player_starting_position()
	else:
		return Vector2.ZERO
