# autoload/game_manager.gd
# ========================
# Purpose:
#   Core game management system that controls game state, levels, and gameplay systems.
#   Handles the game lifecycle including starting, pausing, ending, and restarting.
#   Updated to work with GameSettings for centralized configuration.
#
# Interface:
#   Signals:
#     - game_started
#     - game_paused
#     - game_resumed
#     - game_over
#     - game_restarted
#     - player_credits_changed(new_amount)
#     - upgrade_purchased(upgrade, component)
#     - save_game_created(save_id)
#     - save_game_loaded(save_id)
#
#   Game Lifecycle Methods:
#     - start_game()
#     - pause_game()
#     - resume_game()
#     - end_game()
#     - restart_game()
#
#   GameSettings Integration:
#     - configure_with_settings(settings)

extends Node

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
var game_settings: GameSettings = null

# Start position override from Main.gd
var player_start_position: Vector2 = Vector2.ZERO
var player_start_cell: Vector2i = Vector2i(-1, -1)
var use_custom_start_position: bool = false

# Upgrade system
var available_upgrades: Array = []
var player_upgrades: Array = []

# Dependency checks to avoid circular references
var _dependencies_initialized: bool = false
var _entities_ready: bool = false
var _resources_ready: bool = false
var _events_ready: bool = false
var _seed_ready: bool = false

# System initialization
func _ready() -> void:
	# Make sure systems are initialized in the right order
	call_deferred("_initialize_systems")

func _initialize_systems() -> void:
	# Find GameSettings in the main scene
	var main_scene = get_tree().current_scene
	game_settings = main_scene.get_node_or_null("GameSettings")
	
	# Check which systems are available
	_check_dependencies()
	
	# Initialize entities first
	if _entities_ready:
		_initialize_entity_scenes()
	
	# Connect Events signals
	if _events_ready:
		_connect_event_signals()
	
	# Connect Resources signals
	if _resources_ready:
		_connect_resource_signals()
	
	# Initialize available upgrades
	_initialize_available_upgrades()
	
	_dependencies_initialized = true
	print("GameManager: Systems initialized successfully")

func _check_dependencies() -> void:
	# Check if we have the necessary autoloads
	_entities_ready = has_node("/root/EntityManager")
	_resources_ready = has_node("/root/ResourceManager")
	_events_ready = has_node("/root/EventManager")
	_seed_ready = has_node("/root/SeedManager")
	
	var missing = []
	if not _entities_ready: missing.append("EntityManager")
	if not _resources_ready: missing.append("ResourceManager")
	if not _events_ready: missing.append("EventManager")
	if not _seed_ready: missing.append("SeedManager")
	
	if not missing.is_empty():
		push_warning("GameManager: Missing dependencies: " + ", ".join(missing))

func _initialize_entity_scenes() -> void:
	if has_node("/root/EntityManager"):
		if EntityManager.has_method("_initialize_scenes"):
			if not EntityManager._scenes_initialized:
				EntityManager._initialize_scenes()

func _connect_event_signals() -> void:
	if has_node("/root/EventManager"):
		# A safer way to connect signals with error checking
		var signals_to_connect = {
			"credits_changed": _on_player_credits_changed,
			"player_died": _on_player_died,
		}
		
		for signal_name in signals_to_connect:
			if EventManager.has_signal(signal_name):
				if not EventManager.is_connected(signal_name, signals_to_connect[signal_name]):
					EventManager.connect(signal_name, signals_to_connect[signal_name])
			else:
				push_warning("GameManager: EventManager is missing signal: " + signal_name)

func _connect_resource_signals() -> void:
	if has_node("/root/ResourceManager"):
		if ResourceManager.has_signal("resource_changed"):
			if not ResourceManager.is_connected("resource_changed", _on_resource_changed):
				ResourceManager.resource_changed.connect(_on_resource_changed)
		else:
			push_warning("GameManager: ResourceManager is missing signal: resource_changed")

# Configure with GameSettings
func configure_with_settings(settings: GameSettings) -> void:
	game_settings = settings
	
	if game_settings.debug_mode:
		print("GameManager: Configured with GameSettings")
	
	# Update SeedManager with our settings if available
	if _seed_ready:
		SeedManager.set_seed(game_settings.get_seed())
		
		# Connect to settings seed changes
		if not game_settings.is_connected("seed_changed", _on_settings_seed_changed):
			game_settings.connect("seed_changed", _on_settings_seed_changed)

func _on_settings_seed_changed(new_seed: int) -> void:
	# Update SeedManager if it exists
	if _seed_ready:
		SeedManager.set_seed(new_seed)

# Set the player's start position from Main.gd
func set_player_start_position(position: Vector2, cell: Vector2i = Vector2i(-1, -1)) -> void:
	player_start_position = position
	player_start_cell = cell
	use_custom_start_position = true
	
	if game_settings and game_settings.debug_mode:
		print("GameManager: Player start position set to ", position, " (cell: ", cell, ")")

# Game lifecycle methods
func start_game() -> void:
	if game_running:
		return
	
	# Make sure dependencies are initialized
	if not _dependencies_initialized:
		_initialize_systems()
	
	# Reset game state
	game_running = true
	is_game_paused = false
	player_upgrades.clear()
	
	# Determine spawn position
	var spawn_position = Vector2.ZERO
	
	# First priority: Use custom start position from Main.gd if available
	if use_custom_start_position and player_start_position != Vector2.ZERO:
		spawn_position = player_start_position
	# Second priority: Use GameSettings
	elif game_settings:
		spawn_position = game_settings.get_player_starting_position()
	# Last resort: Use viewport center
	else:
		var viewport_size = get_viewport().get_visible_rect().size
		spawn_position = viewport_size / 2
	
	# Spawn the player at the determined position
	if _entities_ready:
		player_ship = EntityManager.spawn_player(spawn_position)
		if game_settings and game_settings.debug_mode:
			print("GameManager: Spawned player at position: ", spawn_position)
	else:
		push_error("GameManager: Cannot spawn player - EntityManager autoload not found")
		return
	
	# Initialize resources
	if _resources_ready:
		# Clear inventory
		for resource_id in ResourceManager.resource_data:
			ResourceManager.inventory[resource_id] = 0
		
		# Set starting resources from GameSettings if available
		if game_settings:
			ResourceManager.add_resource(ResourceManager.ResourceType.CREDITS, game_settings.player_starting_credits)
			ResourceManager.add_resource(ResourceManager.ResourceType.FUEL, game_settings.player_starting_fuel)
		else:
			# Default starting resources
			ResourceManager.add_resource(ResourceManager.ResourceType.CREDITS, 1000)
			ResourceManager.add_resource(ResourceManager.ResourceType.FUEL, 100)
	
	# Emit game started signal
	game_started.emit()
	if _events_ready:
		EventManager.safe_emit("game_started")
	
	print("GameManager: Game started successfully")

func pause_game() -> void:
	if not game_running or is_game_paused:
		return
	
	# Pause the game
	is_game_paused = true
	get_tree().paused = true
	
	# Emit game paused signal
	game_paused.emit()
	if _events_ready:
		EventManager.safe_emit("game_paused")

func resume_game() -> void:
	if not game_running or not is_game_paused:
		return
	
	# Resume the game
	is_game_paused = false
	get_tree().paused = false
	
	# Emit game resumed signal
	game_resumed.emit()
	if _events_ready:
		EventManager.safe_emit("game_resumed")

func end_game() -> void:
	if not game_running:
		return
	
	# End the game
	game_running = false
	is_game_paused = false
	get_tree().paused = false
	
	# Emit game over signal
	game_over.emit()
	if _events_ready:
		EventManager.safe_emit("game_over")

func restart_game() -> void:
	# End the current game
	if game_running:
		end_game()
	
	# Clear all entities
	if _entities_ready:
		EntityManager.despawn_all()
	
	# Start a new game
	start_game()
	
	# Emit game restarted signal
	game_restarted.emit()
	if _events_ready:
		EventManager.safe_emit("game_restarted")

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
		elif game_settings:
			respawn_position = game_settings.get_player_starting_position()
		else:
			var viewport_size = get_viewport().get_visible_rect().size
			respawn_position = viewport_size / 2
			
		player_ship.respawn(respawn_position)
	else:
		# End the game if player is no longer valid
		end_game()

func _on_player_earned_credits(amount: float) -> void:
	if _resources_ready:
		ResourceManager.add_resource(ResourceManager.ResourceType.CREDITS, amount)

func _on_player_spent_credits(amount: float) -> void:
	if _resources_ready:
		ResourceManager.remove_resource(ResourceManager.ResourceType.CREDITS, amount)

func _on_player_credits_changed(new_amount: float) -> void:
	player_credits_changed.emit(new_amount)

func _on_resource_changed(resource_id: int, new_amount: float, _old_amount: float) -> void:
	# Handle resource changes
	if _resources_ready and resource_id == ResourceManager.ResourceType.CREDITS:
		player_credits_changed.emit(new_amount)
		if _events_ready:
			EventManager.safe_emit("credits_changed", [new_amount])

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
		# We don't need the base class instance, we can directly access inner classes
		var double_damage = weapon_strategies_script.DoubleDamageStrategy.new()
		var rapid_fire = weapon_strategies_script.RapidFireStrategy.new()
		var piercing_shot = weapon_strategies_script.PiercingShotStrategy.new()
		var spread_shot = weapon_strategies_script.SpreadShotStrategy.new()
		
		available_upgrades.append(double_damage)
		available_upgrades.append(rapid_fire)
		available_upgrades.append(piercing_shot)
		available_upgrades.append(spread_shot)
	
	# Create instances of shield strategies
	if shield_strategies_script:
		# We don't need the base class instance, we can directly access inner classes
		var reinforced_shield = shield_strategies_script.ReinforcedShieldStrategy.new()
		var fast_recharge = shield_strategies_script.FastRechargeStrategy.new()
		var reflective_shield = shield_strategies_script.ReflectiveShieldStrategy.new()
		var absorbent_shield = shield_strategies_script.AbsorbentShieldStrategy.new()
		
		available_upgrades.append(reinforced_shield)
		available_upgrades.append(fast_recharge)
		available_upgrades.append(reflective_shield)
		available_upgrades.append(absorbent_shield)
	
	# Create instances of movement strategies
	if movement_strategies_script:
		# We don't need the base class instance, we can directly access inner classes
		var enhanced_thrusters = movement_strategies_script.EnhancedThrustersStrategy.new()
		var maneuverability = movement_strategies_script.ManeuverabilityStrategy.new()
		var afterburner = movement_strategies_script.AfterburnerStrategy.new()
		var inertial_dampeners = movement_strategies_script.InertialDampenersStrategy.new()
		
		available_upgrades.append(enhanced_thrusters)
		available_upgrades.append(maneuverability)
		available_upgrades.append(afterburner)
		available_upgrades.append(inertial_dampeners)

# Upgrade management
func purchase_upgrade(upgrade_index: int, component_name: String) -> bool:
	if upgrade_index < 0 or upgrade_index >= available_upgrades.size():
		return false
	
	var upgrade = available_upgrades[upgrade_index]
	
	# Check if player has enough credits
	if _resources_ready and not ResourceManager.has_resource(ResourceManager.ResourceType.CREDITS, upgrade.price):
		return false
	
	# Apply the upgrade to the player ship
	if player_ship and is_instance_valid(player_ship):
		if player_ship.add_upgrade_strategy(upgrade, component_name):
			# Deduct credits
			if _resources_ready:
				ResourceManager.remove_resource(ResourceManager.ResourceType.CREDITS, upgrade.price)
			
			# Add to player's upgrades
			player_upgrades.append({
				"upgrade": upgrade,
				"component": component_name
			})
			
			# Emit event
			upgrade_purchased.emit(upgrade, component_name)
			if _events_ready:
				EventManager.safe_emit("upgrade_purchased", [upgrade, component_name, upgrade.price])
				EventManager.safe_emit("credits_changed", [ResourceManager.get_resource_amount(ResourceManager.ResourceType.CREDITS)])
			
			return true
	
	return false

func remove_upgrade(upgrade_index: int) -> bool:
	if upgrade_index < 0 or upgrade_index >= player_upgrades.size():
		return false
	
	var upgrade_info = player_upgrades[upgrade_index]
	
	if player_ship and is_instance_valid(player_ship):
		player_ship.remove_upgrade_strategy(upgrade_info.upgrade)
		if _events_ready:
			EventManager.safe_emit("upgrade_removed", [upgrade_info.upgrade, upgrade_info.component])
		player_upgrades.remove_at(upgrade_index)
		return true
	
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
		"resources": ResourceManager.inventory if _resources_ready else {},
		"seed": game_settings.get_seed() if game_settings else (SeedManager.get_seed() if _seed_ready else 0),
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
		if game_settings:
			game_settings.set_seed(save_data.seed)
		elif _seed_ready:
			SeedManager.set_seed(save_data.seed)
	
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
	if _resources_ready and save_data.has("resources"):
		for resource_id in save_data.resources:
			ResourceManager.inventory[int(resource_id)] = save_data.resources[resource_id]
	
	save_game_loaded.emit(save_id)
	return true

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
