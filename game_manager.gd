# game_manager.gd
extends Node
class_name GameManager

signal game_started
signal game_paused
signal game_resumed
signal game_over
signal game_restarted
signal player_credits_changed(new_amount)

# Core systems
@onready var entity_manager: EntityManager = $EntityManager
@onready var event_system: EventSystem = $EventSystem
@onready var resource_manager: ResourceManager = $ResourceManager

# Game state
var game_running: bool = false
var game_paused: bool = false
var current_level: String = ""
var player_ship: PlayerShip = null

# Upgrade system
var available_upgrades: Array = []
var player_upgrades: Array = []

func _ready() -> void:
	# Set up event connections
	if event_system:
		event_system.register_event("player_earned_credits")
		event_system.register_event("player_spent_credits")
		event_system.register_event("asteroid_mined")
		event_system.register_event("enemy_destroyed")
		event_system.register_event("trade_completed")
		
		# Connect events to local methods
		event_system.connect_event("player_earned_credits", _on_player_earned_credits)
		event_system.connect_event("player_spent_credits", _on_player_spent_credits)
	
	# Connect signals from resource manager
	if resource_manager:
		resource_manager.resource_changed.connect(_on_resource_changed)
	
	# Connect to entity manager signals
	if entity_manager:
		entity_manager.player_spawned.connect(_on_player_spawned)
	
	# Initialize available upgrades
	_initialize_available_upgrades()
	
	# Wait one frame to ensure all systems are ready
	await get_tree().process_frame
	
	# Auto-start the game if needed
	# start_game()

func start_game() -> void:
	if game_running:
		return
	
	# Reset game state
	game_running = true
	game_paused = false
	player_upgrades.clear()
	
	# Spawn the player
	if entity_manager:
		var viewport_size = get_viewport().get_visible_rect().size
		player_ship = entity_manager.spawn_player(viewport_size / 2)
	
	# Initialize resources
	if resource_manager:
		# Clear inventory
		for resource_id in resource_manager.resource_data:
			resource_manager.inventory[resource_id] = 0
		
		# Set starting resources
		resource_manager.add_resource(resource_manager.ResourceType.CREDITS, 1000)  # Starting credits
		resource_manager.add_resource(resource_manager.ResourceType.FUEL, 100)      # Starting fuel
	
	# Emit game started signal
	game_started.emit()

func pause_game() -> void:
	if not game_running or game_paused:
		return
	
	# Pause the game
	game_paused = true
	get_tree().paused = true
	
	# Emit game paused signal
	game_paused.emit()

func resume_game() -> void:
	if not game_running or not game_paused:
		return
	
	# Resume the game
	game_paused = false
	get_tree().paused = false
	
	# Emit game resumed signal
	game_resumed.emit()

func end_game() -> void:
	if not game_running:
		return
	
	# End the game
	game_running = false
	game_paused = false
	get_tree().paused = false
	
	# Emit game over signal
	game_over.emit()

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

func _on_player_spawned(player) -> void:
	player_ship = player
	
	# Connect player signals
	player_ship.player_died.connect(_on_player_died)

func _on_player_died() -> void:
	# Handle player death
	# Could trigger game over or respawn after delay
	await get_tree().create_timer(3.0).timeout
	
	if player_ship and is_instance_valid(player_ship):
		# Respawn the player
		var viewport_size = get_viewport().get_visible_rect().size
		player_ship.respawn(viewport_size / 2)
	else:
		# End the game if player is no longer valid
		end_game()

func _on_player_earned_credits(amount: float) -> void:
	if resource_manager:
		resource_manager.add_resource(resource_manager.ResourceType.CREDITS, amount)

func _on_player_spent_credits(amount: float) -> void:
	if resource_manager:
		resource_manager.remove_resource(resource_manager.ResourceType.CREDITS, amount)

func _on_resource_changed(resource_id: int, new_amount: float, old_amount: float) -> void:
	# Handle resource changes
	if resource_id == resource_manager.ResourceType.CREDITS:
		player_credits_changed.emit(new_amount)

func _initialize_available_upgrades() -> void:
	# Weapon upgrades
	available_upgrades.append(WeaponStrategies.DoubleDamageStrategy.new())
	available_upgrades.append(WeaponStrategies.RapidFireStrategy.new())
	available_upgrades.append(WeaponStrategies.PiercingShotStrategy.new())
	available_upgrades.append(WeaponStrategies.SpreadShotStrategy.new())
	
	# Shield upgrades
	available_upgrades.append(ShieldStrategies.ReinforcedShieldStrategy.new())
	available_upgrades.append(ShieldStrategies.FastRechargeStrategy.new())
	available_upgrades.append(ShieldStrategies.ReflectiveShieldStrategy.new())
	available_upgrades.append(ShieldStrategies.AbsorbentShieldStrategy.new())
	
	# Movement upgrades
	available_upgrades.append(MovementStrategies.EnhancedThrustersStrategy.new())
	available_upgrades.append(MovementStrategies.ManeuverabilityStrategy.new())
	available_upgrades.append(MovementStrategies.AfterburnerStrategy.new())
	available_upgrades.append(MovementStrategies.InertialDampenersStrategy.new())

func purchase_upgrade(upgrade_index: int, component_name: String) -> bool:
	if upgrade_index < 0 or upgrade_index >= available_upgrades.size():
		return false
	
	var upgrade = available_upgrades[upgrade_index]
	
	# Check if player has enough credits
	if resource_manager:
		if not resource_manager.has_resource(resource_manager.ResourceType.CREDITS, upgrade.price):
			return false
	
	# Apply the upgrade to the player ship
	if player_ship and is_instance_valid(player_ship):
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
			if event_system:
				event_system.emit_event("player_spent_credits", [upgrade.price])
			
			return true
	
	return false

func remove_upgrade(upgrade_index: int) -> bool:
	if upgrade_index < 0 or upgrade_index >= player_upgrades.size():
		return false
	
	var upgrade_info = player_upgrades[upgrade_index]
	
	if player_ship and is_instance_valid(player_ship):
		player_ship.remove_upgrade_strategy(upgrade_info.upgrade)
		player_upgrades.remove_at(upgrade_index)
		return true
	
	return false

func get_available_upgrades_for_component(component_name: String) -> Array:
	var filtered_upgrades = []
	
	for upgrade in available_upgrades:
		# Filter based on component type
		match component_name:
			"WeaponComponent":
				if upgrade is WeaponStrategies.DoubleDamageStrategy or \
				   upgrade is WeaponStrategies.RapidFireStrategy or \
				   upgrade is WeaponStrategies.PiercingShotStrategy or \
				   upgrade is WeaponStrategies.SpreadShotStrategy:
					filtered_upgrades.append(upgrade)
			
			"ShieldComponent":
				if upgrade is ShieldStrategies.ReinforcedShieldStrategy or \
				   upgrade is ShieldStrategies.FastRechargeStrategy or \
				   upgrade is ShieldStrategies.ReflectiveShieldStrategy or \
				   upgrade is ShieldStrategies.AbsorbentShieldStrategy:
					filtered_upgrades.append(upgrade)
			
			"MovementComponent":
				if upgrade is MovementStrategies.EnhancedThrustersStrategy or \
				   upgrade is MovementStrategies.ManeuverabilityStrategy or \
				   upgrade is MovementStrategies.AfterburnerStrategy or \
				   upgrade is MovementStrategies.InertialDampenersStrategy:
					filtered_upgrades.append(upgrade)
	
	return filtered_upgrades

func _input(event: InputEvent) -> void:
	# Handle game pause/resume input
	if event.is_action_pressed("pause"):
		if game_running:
			if game_paused:
				resume_game()
			else:
				pause_game()
	
	# Debug inputs
	if OS.is_debug_build():
		if event.is_action_pressed("debug_restart_game"):
			restart_game()
		elif event.is_action_pressed("debug_quit_game"):
			get_tree().quit()
