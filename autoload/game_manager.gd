extends Node

# Game lifecycle signals
signal game_started
signal game_paused
signal game_resumed
signal game_over
signal game_restarted
signal save_game_created(save_id)
signal save_game_loaded(save_id)

# Game state signals
signal player_credits_changed(new_amount)
signal player_fuel_changed(new_amount)
signal player_resource_changed(resource_id, new_amount, old_amount)
signal upgrade_purchased(upgrade, component, cost)
signal world_generation_completed

# Game state
var game_running: bool = false
var is_game_paused: bool = false
var current_level: String = ""
var player_ship = null
var game_settings = null

# World state
var world_data: WorldData = null
var current_seed: int = 0

# Start position
var player_start_position: Vector2 = Vector2.ZERO
var player_start_cell: Vector2i = Vector2i(-1, -1)
var use_custom_start_position: bool = false

# Upgrade system
var available_upgrades = []
var player_upgrades = []

# Dependency checks
var _dependencies_initialized: bool = false
var _entities_ready: bool = false
var _resources_ready: bool = false
var _events_ready: bool = false
var _world_ready: bool = false
var _seed_ready: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_initialize_systems")

func _initialize_systems() -> void:
	# Find GameSettings in the main scene
	var main_scene = get_tree().current_scene
	game_settings = main_scene.get_node_or_null("GameSettings")
	
	# Check which systems are available
	_check_dependencies()
	
	# Initialize in the right order
	if _entities_ready:
		_initialize_entity_scenes()
	
	if _events_ready:
		_connect_event_signals()
	
	if _resources_ready:
		_connect_resource_signals()
	
	_initialize_available_upgrades()
	
	_dependencies_initialized = true

func _check_dependencies() -> void:
	_entities_ready = has_node("/root/EntityManager")
	_resources_ready = has_node("/root/ResourceManager")
	_events_ready = has_node("/root/EventManager")
	_seed_ready = has_node("/root/SeedManager")
	_world_ready = has_node("/root/WorldManager")

func _initialize_entity_scenes() -> void:
	if has_node("/root/EntityManager"):
		if not EntityManager._scenes_initialized:
			EntityManager._initialize_scenes()

func _connect_event_signals() -> void:
	if has_node("/root/EventManager"):
		# Connect crucial signals
		if EventManager.has_signal("credits_changed"):
			if not EventManager.is_connected("credits_changed", _on_player_credits_changed):
				EventManager.connect("credits_changed", _on_player_credits_changed)
				
		if EventManager.has_signal("player_died"):
			if not EventManager.is_connected("player_died", _on_player_died):
				EventManager.connect("player_died", _on_player_died)

func _connect_resource_signals() -> void:
	if has_node("/root/ResourceManager"):
		if ResourceManager.has_signal("resource_changed"):
			if not ResourceManager.is_connected("resource_changed", _on_resource_changed):
				ResourceManager.resource_changed.connect(_on_resource_changed)

# Configure with GameSettings
func configure_with_settings(settings) -> void:
	game_settings = settings
	
	# Wait for SeedManager if needed
	if _seed_ready and has_node("/root/SeedManager"):
		if not SeedManager.is_initialized:
			if SeedManager.has_signal("seed_initialized"):
				await SeedManager.seed_initialized
		
		# Update seed
		current_seed = game_settings.get_seed()
		SeedManager.set_seed(current_seed)
		
		# Connect to settings seed changes
		if not game_settings.is_connected("seed_changed", _on_settings_seed_changed):
			game_settings.connect("seed_changed", _on_settings_seed_changed)

func _on_settings_seed_changed(new_seed: int) -> void:
	current_seed = new_seed
	
	if _seed_ready and has_node("/root/SeedManager"):
		SeedManager.set_seed(new_seed)

# Set the player's start position
func set_player_start_position(position: Vector2, cell: Vector2i = Vector2i(-1, -1)) -> void:
	player_start_position = position
	player_start_cell = cell
	use_custom_start_position = true
	
	# Update world data if it exists
	if world_data:
		world_data.player_start_position = position
		world_data.player_start_cell = cell

# Game lifecycle methods
func start_game() -> void:
	if game_running:
		return
	
	# Initialize dependencies if needed
	if not _dependencies_initialized:
		_initialize_systems()
	
	# Reset game state
	game_running = true
	is_game_paused = false
	player_upgrades.clear()
	
	# Set seed
	if _seed_ready and game_settings:
		current_seed = game_settings.get_seed()
		SeedManager.set_seed(current_seed)
	
	# Generate or load world
	if not world_data:
		_generate_world()
	else:
		_load_world(world_data)
	
	# Initialize resources
	if _resources_ready:
		_initialize_resources()
	
	# Emit signals
	game_started.emit()
	if _events_ready:
		EventManager.safe_emit("game_started")

func _generate_world() -> void:
	# Get seed from GameSettings or use default
	var seed_value = current_seed
	if game_settings:
		seed_value = game_settings.get_seed()
	
	# Generate world data using WorldManager
	world_data = WorldManager.generate_world(seed_value)
	
	# Set start position if specified
	if use_custom_start_position:
		world_data.player_start_position = player_start_position
		world_data.player_start_cell = player_start_cell
	
	# Load the generated world
	_load_world(world_data)

func _load_world(data: WorldData) -> void:
	# Load world in WorldManager
	if WorldManager.load_world(data):
		# Connect to world_ready signal
		if not WorldManager.is_connected("world_ready", _on_world_loaded):
			WorldManager.connect("world_ready", _on_world_loaded)
	else:
		# If no simulation available, spawn player directly
		_spawn_player_at_start_position()

func _on_world_loaded() -> void:
	# Spawn player
	_spawn_player_at_start_position()
	
	# Emit world generation completed signal
	world_generation_completed.emit()

func _spawn_player_at_start_position() -> void:
	# Determine spawn position
	var spawn_position = Vector2.ZERO
	
	if world_data and world_data.player_start_position != Vector2.ZERO:
		spawn_position = world_data.player_start_position
	elif use_custom_start_position and player_start_position != Vector2.ZERO:
		spawn_position = player_start_position
	elif game_settings:
		spawn_position = game_settings.get_player_starting_position()
	else:
		spawn_position = get_viewport().get_visible_rect().size / 2
	
	# Spawn player
	if _entities_ready:
		player_ship = EntityManager.spawn_player(spawn_position)
	else:
		push_error("GameManager: Cannot spawn player - EntityManager not found")

func _initialize_resources() -> void:
	# Clear inventory
	for resource_id in ResourceManager.resource_data:
		ResourceManager.inventory[resource_id] = 0
	
	# Set starting resources
	if game_settings:
		ResourceManager.add_resource(ResourceManager.ResourceType.CREDITS, game_settings.player_starting_credits)
		ResourceManager.add_resource(ResourceManager.ResourceType.FUEL, game_settings.player_starting_fuel)
	else:
		ResourceManager.add_resource(ResourceManager.ResourceType.CREDITS, 1000)
		ResourceManager.add_resource(ResourceManager.ResourceType.FUEL, 100)

func pause_game() -> void:
	if not game_running or is_game_paused:
		return
	
	is_game_paused = true
	get_tree().paused = true
	
	game_paused.emit()
	if _events_ready:
		EventManager.safe_emit("game_paused")

func resume_game() -> void:
	if not game_running or not is_game_paused:
		return
	
	is_game_paused = false
	get_tree().paused = false
	
	game_resumed.emit()
	if _events_ready:
		EventManager.safe_emit("game_resumed")

func end_game() -> void:
	if not game_running:
		return
	
	game_running = false
	is_game_paused = false
	get_tree().paused = false
	
	game_over.emit()
	if _events_ready:
		EventManager.safe_emit("game_over")

func restart_game() -> void:
	if game_running:
		end_game()
	
	# Clear world 
	WorldManager.reset_world()
	
	# Clear entity manager
	if _entities_ready:
		EntityManager.despawn_all()
	
	# Generate new world
	world_data = null
	
	# Start game again
	start_game()
	
	game_restarted.emit()
	if _events_ready:
		EventManager.safe_emit("game_restarted")

# Event handlers
func _on_world_generation_completed() -> void:
	if game_settings and game_settings.debug_mode:
		print("GameManager: World generation completed")

func _on_entity_spawned(entity: Node, data: EntityData) -> void:
	# Register with EntityManager if available
	if _entities_ready and data:
		EntityManager.register_entity(entity, data.entity_type)
		
		# Handle specific entity types
		if data is PlanetData:
			if entity.has_method("set_planet_data"):
				entity.set_planet_data(data)

func _on_entity_despawned(entity: Node, data: EntityData) -> void:
	# Deregister from EntityManager
	if _entities_ready:
		EntityManager.deregister_entity(entity)

func _on_player_spawned(player) -> void:
	player_ship = player
	
	if player_ship and is_instance_valid(player_ship):
		if player_ship.has_signal("player_died") and not player_ship.player_died.is_connected(_on_player_died):
			player_ship.player_died.connect(_on_player_died)

func _on_player_died() -> void:
	await get_tree().create_timer(3.0).timeout
	
	if player_ship and is_instance_valid(player_ship):
		# Respawn the player
		var respawn_position
		
		if world_data and world_data.player_start_position != Vector2.ZERO:
			respawn_position = world_data.player_start_position
		elif use_custom_start_position and player_start_position != Vector2.ZERO:
			respawn_position = player_start_position
		elif game_settings:
			respawn_position = game_settings.get_player_starting_position()
		else:
			respawn_position = get_viewport().get_visible_rect().size / 2
			
		player_ship.respawn(respawn_position)
	else:
		end_game()

func _on_player_credits_changed(new_amount) -> void:
	player_credits_changed.emit(new_amount)

func _on_resource_changed(resource_id, new_amount, old_amount) -> void:
	player_resource_changed.emit(resource_id, new_amount, old_amount)
	
	if _resources_ready and resource_id == ResourceManager.ResourceType.CREDITS:
		player_credits_changed.emit(new_amount)
		if _events_ready:
			EventManager.safe_emit("credits_changed", [new_amount])
	
	if _resources_ready and resource_id == ResourceManager.ResourceType.FUEL:
		player_fuel_changed.emit(new_amount)

# Upgrade system
func _initialize_available_upgrades() -> void:
	# Load script resources
	var weapon_strategies_script = load("res://scripts/strategies/weapon_strategies.gd")
	var shield_strategies_script = load("res://scripts/strategies/shield_strategies.gd")
	var movement_strategies_script = load("res://scripts/strategies/movement_strategies.gd")
	
	if not weapon_strategies_script or not shield_strategies_script or not movement_strategies_script:
		return
	
	# Create instances of weapon strategies
	if weapon_strategies_script:
		available_upgrades.append_array([
			weapon_strategies_script.DoubleDamageStrategy.new(),
			weapon_strategies_script.RapidFireStrategy.new(),
			weapon_strategies_script.PiercingShotStrategy.new(),
			weapon_strategies_script.SpreadShotStrategy.new()
		])
	
	# Create instances of shield strategies
	if shield_strategies_script:
		available_upgrades.append_array([
			shield_strategies_script.ReinforcedShieldStrategy.new(),
			shield_strategies_script.FastRechargeStrategy.new(),
			shield_strategies_script.ReflectiveShieldStrategy.new(),
			shield_strategies_script.AbsorbentShieldStrategy.new()
		])
	
	# Create instances of movement strategies
	if movement_strategies_script:
		available_upgrades.append_array([
			movement_strategies_script.EnhancedThrustersStrategy.new(),
			movement_strategies_script.ManeuverabilityStrategy.new(),
			movement_strategies_script.AfterburnerStrategy.new(),
			movement_strategies_script.InertialDampenersStrategy.new()
		])

# Upgrade management
func purchase_upgrade(upgrade_index, component_name) -> bool:
	if upgrade_index < 0 or upgrade_index >= available_upgrades.size():
		return false
	
	var upgrade = available_upgrades[upgrade_index]
	
	# Check player credits
	if _resources_ready and not ResourceManager.has_resource(ResourceManager.ResourceType.CREDITS, upgrade.price):
		return false
	
	# Apply the upgrade
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
			
			# Emit events
			upgrade_purchased.emit(upgrade, component_name, upgrade.price)
			if _events_ready:
				EventManager.safe_emit("upgrade_purchased", [upgrade, component_name, upgrade.price])
				EventManager.safe_emit("credits_changed", [ResourceManager.get_resource_amount(ResourceManager.ResourceType.CREDITS)])
			
			return true
	
	return false

func remove_upgrade(upgrade_index) -> bool:
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

func get_available_upgrades_for_component(component_name) -> Array:
	var filtered_upgrades = []
	
	for upgrade in available_upgrades:
		var upgrade_script = upgrade.get_script()
		if upgrade_script == null:
			continue
			
		var script_path = upgrade_script.resource_path
		
		# Filter based on script path
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

# Save/Load functionality
func save_game(save_id: String = "") -> bool:
	if not game_running:
		return false
	
	# Generate ID if needed
	if save_id.is_empty():
		save_id = "save_" + Time.get_datetime_string_from_system().replace(":", "-")
	
	# Update world data from current state
	WorldManager._update_world_data_from_entities()
	
	# Collect game state
	var save_data = {
		"version": "1.0",
		"timestamp": Time.get_unix_time_from_system(),
		"player": {
			"position": player_ship.global_position if player_ship else Vector2.ZERO,
			"upgrades": player_upgrades,
		},
		"resources": ResourceManager.inventory if _resources_ready else {},
		"seed": game_settings.get_seed() if game_settings else (SeedManager.get_seed() if _seed_ready else 0),
		"world_data": world_data.to_dict() if world_data else {}
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
	
	if not save_data is Dictionary or not save_data.has("version"):
		push_error("GameManager: Invalid save file format")
		return false
	
	# End current game if running
	if game_running:
		end_game()
	
	# Restore seed
	if save_data.has("seed"):
		current_seed = save_data.seed
		if game_settings:
			game_settings.set_seed(current_seed)
		elif _seed_ready:
			SeedManager.set_seed(current_seed)
	
	# Restore world data if present
	if save_data.has("world_data") and not save_data.world_data.is_empty():
		world_data = WorldData.from_dict(save_data.world_data)
	
	# Start a new game
	start_game()
	
	# Restore player state
	if save_data.has("player") and player_ship:
		if save_data.player.has("position"):
			player_ship.global_position = save_data.player.position
		
		# Restore upgrades
		if save_data.player.has("upgrades"):
			player_upgrades = save_data.player.upgrades.duplicate()
			for upgrade_info in player_upgrades:
				if player_ship.has_method("add_upgrade_strategy"):
					player_ship.add_upgrade_strategy(upgrade_info.upgrade, upgrade_info.component)
	
	# Restore resources
	if _resources_ready and save_data.has("resources"):
		for resource_id in save_data.resources:
			ResourceManager.inventory[int(resource_id)] = save_data.resources[resource_id]
			
			# Notify of changes
			if int(resource_id) == ResourceManager.ResourceType.CREDITS:
				player_credits_changed.emit(save_data.resources[resource_id])
			
			if _events_ready:
				EventManager.safe_emit("resource_changed", [int(resource_id), save_data.resources[resource_id], 0])
	
	save_game_loaded.emit(save_id)
	return true

# Helper methods
func get_player_ship():
	return player_ship

# Input handling
func _input(event: InputEvent) -> void:
	# Handle game pause/resume
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
