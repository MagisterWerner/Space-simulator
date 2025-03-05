# autoload/game_manager.gd
#
# GameManager Singleton
# =====================
# Purpose:
#   Manages the overall game state, lifecycle, and upgrade system.
#   Serves as the central authority for gameplay mechanics and progression.
#
# Interface:
#   - Game State Management: start_game(), pause_game(), resume_game(), end_game(), restart_game()
#   - Upgrade System: purchase_upgrade(), remove_upgrade(), get_available_upgrades_for_component()
#   - Signals: game_started, game_paused, game_resumed, game_over, game_restarted, player_credits_changed
#
# Usage:
#   Access via the GameManager autoload:
#   ```
#   # Start a new game
#   GameManager.start_game()
#
#   # Purchase an upgrade for a component
#   GameManager.purchase_upgrade(upgrade_index, component_name)
#   ```
#
extends Node
class_name GameManagerSingleton

signal game_started
signal game_paused
signal game_resumed
signal game_over
signal game_restarted
signal player_credits_changed(new_amount)

# Game state
var game_running: bool = false
var is_game_paused: bool = false  # Renamed from game_paused to avoid conflict with signal
var current_level: String = ""
var player_ship: PlayerShip = null

# Upgrade system
var available_upgrades: Array = []
var player_upgrades: Array = []

func _ready() -> void:
	# Make sure systems are initialized in the right order
	call_deferred("_initialize_systems")

func _initialize_systems() -> void:
	# Ensure Entities has access to required scenes
	_initialize_entity_scenes()
	
	# Set up event connections from the Events autoload
	Events.credits_changed.connect(_on_player_credits_changed)
	Events.player_died.connect(_on_player_died)
	
	# Connect signals from Resources autoload
	Resources.resource_changed.connect(_on_resource_changed)
	
	# Connect to Entities autoload signals
	Entities.player_spawned.connect(_on_player_spawned)
	
	# Initialize available upgrades
	_initialize_available_upgrades()

func _initialize_entity_scenes() -> void:
	# Make sure the entity scenes are set correctly
	if not Entities._scenes_initialized:
		Entities._initialize_scenes()

func start_game() -> void:
	if game_running:
		return
	
	# Reset game state
	game_running = true
	is_game_paused = false
	player_upgrades.clear()
	
	# Ensure entity scenes are initialized
	_initialize_entity_scenes()
	
	# Spawn the player
	var viewport_size = get_viewport().get_visible_rect().size
	player_ship = Entities.spawn_player(viewport_size / 2)
	
	# Initialize resources
	# Clear inventory
	for resource_id in Resources.resource_data:
		Resources.inventory[resource_id] = 0
	
	# Set starting resources
	Resources.add_resource(Resources.ResourceType.CREDITS, 1000)  # Starting credits
	Resources.add_resource(Resources.ResourceType.FUEL, 100)      # Starting fuel
	
	# Emit game started signal
	game_started.emit()
	Events.game_started.emit()

func pause_game() -> void:
	if not game_running or is_game_paused:
		return
	
	# Pause the game
	is_game_paused = true
	get_tree().paused = true
	
	# Emit game paused signal
	game_paused.emit()
	Events.game_paused.emit()

func resume_game() -> void:
	if not game_running or not is_game_paused:
		return
	
	# Resume the game
	is_game_paused = false
	get_tree().paused = false
	
	# Emit game resumed signal
	game_resumed.emit()
	Events.game_resumed.emit()

func end_game() -> void:
	if not game_running:
		return
	
	# End the game
	game_running = false
	is_game_paused = false
	get_tree().paused = false
	
	# Emit game over signal
	game_over.emit()
	Events.game_over.emit()

func restart_game() -> void:
	# End the current game
	if game_running:
		end_game()
	
	# Clear all entities
	Entities.despawn_all()
	
	# Start a new game
	start_game()
	
	# Emit game restarted signal
	game_restarted.emit()
	Events.game_restarted.emit()

func _on_player_spawned(player) -> void:
	player_ship = player
	
	# Connect player signals
	if player_ship and is_instance_valid(player_ship):
		if not player_ship.player_died.is_connected(_on_player_died):
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
	Resources.add_resource(Resources.ResourceType.CREDITS, amount)

func _on_player_spent_credits(amount: float) -> void:
	Resources.remove_resource(Resources.ResourceType.CREDITS, amount)

func _on_player_credits_changed(new_amount: float) -> void:
	player_credits_changed.emit(new_amount)

func _on_resource_changed(resource_id: int, new_amount: float, _old_amount: float) -> void:
	# Handle resource changes
	if resource_id == Resources.ResourceType.CREDITS:
		player_credits_changed.emit(new_amount)
		Events.credits_changed.emit(new_amount)

func _initialize_available_upgrades() -> void:
	# Create strategy instances
	
	# Weapon upgrades
	var double_damage = WeaponStrategies.DoubleDamageStrategy.new()
	var rapid_fire = WeaponStrategies.RapidFireStrategy.new()
	var piercing_shot = WeaponStrategies.PiercingShotStrategy.new()
	var spread_shot = WeaponStrategies.SpreadShotStrategy.new()
	
	# Shield upgrades
	var reinforced_shield = ShieldStrategies.ReinforcedShieldStrategy.new()
	var fast_recharge = ShieldStrategies.FastRechargeStrategy.new()
	var reflective_shield = ShieldStrategies.ReflectiveShieldStrategy.new()
	var absorbent_shield = ShieldStrategies.AbsorbentShieldStrategy.new()
	
	# Movement upgrades
	var enhanced_thrusters = MovementStrategies.EnhancedThrustersStrategy.new()
	var maneuverability = MovementStrategies.ManeuverabilityStrategy.new()
	var afterburner = MovementStrategies.AfterburnerStrategy.new()
	var inertial_dampeners = MovementStrategies.InertialDampenersStrategy.new()
	
	# Add all strategies to available_upgrades array
	available_upgrades.append(double_damage)
	available_upgrades.append(rapid_fire)
	available_upgrades.append(piercing_shot)
	available_upgrades.append(spread_shot)
	
	available_upgrades.append(reinforced_shield)
	available_upgrades.append(fast_recharge)
	available_upgrades.append(reflective_shield)
	available_upgrades.append(absorbent_shield)
	
	available_upgrades.append(enhanced_thrusters)
	available_upgrades.append(maneuverability)
	available_upgrades.append(afterburner)
	available_upgrades.append(inertial_dampeners)

func purchase_upgrade(upgrade_index: int, component_name: String) -> bool:
	if upgrade_index < 0 or upgrade_index >= available_upgrades.size():
		return false
	
	var upgrade = available_upgrades[upgrade_index]
	
	# Check if player has enough credits
	if not Resources.has_resource(Resources.ResourceType.CREDITS, upgrade.price):
		return false
	
	# Apply the upgrade to the player ship
	if player_ship and is_instance_valid(player_ship):
		if player_ship.add_upgrade_strategy(upgrade, component_name):
			# Deduct credits
			Resources.remove_resource(Resources.ResourceType.CREDITS, upgrade.price)
			
			# Add to player's upgrades
			player_upgrades.append({
				"upgrade": upgrade,
				"component": component_name
			})
			
			# Emit event
			Events.upgrade_purchased.emit(upgrade, component_name, upgrade.price)
			Events.credits_changed.emit(Resources.get_resource_amount(Resources.ResourceType.CREDITS))
			
			return true
	
	return false

func remove_upgrade(upgrade_index: int) -> bool:
	if upgrade_index < 0 or upgrade_index >= player_upgrades.size():
		return false
	
	var upgrade_info = player_upgrades[upgrade_index]
	
	if player_ship and is_instance_valid(player_ship):
		player_ship.remove_upgrade_strategy(upgrade_info.upgrade)
		Events.upgrade_removed.emit(upgrade_info.upgrade, upgrade_info.component)
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
