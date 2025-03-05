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
var player_ship = null  # Changed to avoid type checking issues

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
	if has_node("/root/Events"):
		if Events.has_signal("credits_changed"):
			Events.credits_changed.connect(_on_player_credits_changed)
		
		if Events.has_signal("player_died"):
			Events.player_died.connect(_on_player_died)
	
	# Connect signals from Resources autoload - make sure the signal exists
	if has_node("/root/Resources"):
		if Resources.has_signal("resource_changed"):
			Resources.resource_changed.connect(_on_resource_changed)
	
	# Connect to Entities autoload signals
	if has_node("/root/Entities"):
		if Entities.has_signal("player_spawned"):
			Entities.player_spawned.connect(_on_player_spawned)
	
	# Initialize available upgrades
	_initialize_available_upgrades()

func _initialize_entity_scenes() -> void:
	# Make sure the entity scenes are set correctly
	if has_node("/root/Entities"):
		if Entities.has_method("_initialize_scenes"):
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
	if has_node("/root/Entities"):
		player_ship = Entities.spawn_player(viewport_size / 2)
	
	# Initialize resources
	if has_node("/root/Resources"):
		# Clear inventory
		for resource_id in Resources.resource_data:
			Resources.inventory[resource_id] = 0
		
		# Set starting resources
		Resources.add_resource(Resources.ResourceType.CREDITS, 1000)  # Starting credits
		Resources.add_resource(Resources.ResourceType.FUEL, 100)      # Starting fuel
	
	# Emit game started signal
	game_started.emit()
	if has_node("/root/Events"):
		Events.safe_emit("game_started")

func pause_game() -> void:
	if not game_running or is_game_paused:
		return
	
	# Pause the game
	is_game_paused = true
	get_tree().paused = true
	
	# Emit game paused signal
	game_paused.emit()
	if has_node("/root/Events"):
		Events.safe_emit("game_paused")

func resume_game() -> void:
	if not game_running or not is_game_paused:
		return
	
	# Resume the game
	is_game_paused = false
	get_tree().paused = false
	
	# Emit game resumed signal
	game_resumed.emit()
	if has_node("/root/Events"):
		Events.safe_emit("game_resumed")

func end_game() -> void:
	if not game_running:
		return
	
	# End the game
	game_running = false
	is_game_paused = false
	get_tree().paused = false
	
	# Emit game over signal
	game_over.emit()
	if has_node("/root/Events"):
		Events.safe_emit("game_over")

func restart_game() -> void:
	# End the current game
	if game_running:
		end_game()
	
	# Clear all entities
	if has_node("/root/Entities"):
		Entities.despawn_all()
	
	# Start a new game
	start_game()
	
	# Emit game restarted signal
	game_restarted.emit()
	if has_node("/root/Events"):
		Events.safe_emit("game_restarted")

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
		var viewport_size = get_viewport().get_visible_rect().size
		player_ship.respawn(viewport_size / 2)
	else:
		# End the game if player is no longer valid
		end_game()

func _on_player_earned_credits(amount: float) -> void:
	if has_node("/root/Resources"):
		Resources.add_resource(Resources.ResourceType.CREDITS, amount)

func _on_player_spent_credits(amount: float) -> void:
	if has_node("/root/Resources"):
		Resources.remove_resource(Resources.ResourceType.CREDITS, amount)

func _on_player_credits_changed(new_amount: float) -> void:
	player_credits_changed.emit(new_amount)

func _on_resource_changed(resource_id: int, new_amount: float, _old_amount: float) -> void:
	# Handle resource changes
	if has_node("/root/Resources") and resource_id == Resources.ResourceType.CREDITS:
		player_credits_changed.emit(new_amount)
		if has_node("/root/Events"):
			Events.safe_emit("credits_changed", [new_amount])

func _initialize_available_upgrades() -> void:
	# We need to directly create instances of the strategy classes without relying on ClassDB
	# since these are inner classes
	
	# First check if we have the necessary script resources loaded
	var weapon_strategies_script = load("res://weapon_strategies.gd")
	var shield_strategies_script = load("res://shield_strategies.gd")
	var movement_strategies_script = load("res://movement_strategies.gd")
	
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

func purchase_upgrade(upgrade_index: int, component_name: String) -> bool:
	if upgrade_index < 0 or upgrade_index >= available_upgrades.size():
		return false
	
	var upgrade = available_upgrades[upgrade_index]
	
	# Check if player has enough credits
	if has_node("/root/Resources") and not Resources.has_resource(Resources.ResourceType.CREDITS, upgrade.price):
		return false
	
	# Apply the upgrade to the player ship
	if player_ship and is_instance_valid(player_ship):
		if player_ship.add_upgrade_strategy(upgrade, component_name):
			# Deduct credits
			if has_node("/root/Resources"):
				Resources.remove_resource(Resources.ResourceType.CREDITS, upgrade.price)
			
			# Add to player's upgrades
			player_upgrades.append({
				"upgrade": upgrade,
				"component": component_name
			})
			
			# Emit event
			if has_node("/root/Events"):
				Events.safe_emit("upgrade_purchased", [upgrade, component_name, upgrade.price])
				Events.safe_emit("credits_changed", [Resources.get_resource_amount(Resources.ResourceType.CREDITS)])
			
			return true
	
	return false

func remove_upgrade(upgrade_index: int) -> bool:
	if upgrade_index < 0 or upgrade_index >= player_upgrades.size():
		return false
	
	var upgrade_info = player_upgrades[upgrade_index]
	
	if player_ship and is_instance_valid(player_ship):
		player_ship.remove_upgrade_strategy(upgrade_info.upgrade)
		if has_node("/root/Events"):
			Events.safe_emit("upgrade_removed", [upgrade_info.upgrade, upgrade_info.component])
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
