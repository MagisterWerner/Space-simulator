# scripts/entities/player_ship.gd
extends RigidBody2D
class_name PlayerShip

signal player_damaged(amount)
signal player_died
signal player_respawned
signal weapon_switched(weapon_name)

# Cached component references
@onready var health_component: HealthComponent = $HealthComponent
@onready var movement_component: MovementComponent = $MovementComponent
@onready var shield_component: ShieldComponent = $ShieldComponent
@onready var state_machine: StateMachine = $StateMachine
@onready var weapon_manager: WeaponManagerComponent = null

@export var debug_mode: bool = false
@export var input_enabled: bool = true

# Reference to GameSettings
var game_settings: GameSettings = null

# Input state - packed into bitmask for efficiency
var _input_state: int = 0

# Input flag constants
const INPUT_FORWARD = 1
const INPUT_BACKWARD = 2
const INPUT_LEFT = 4
const INPUT_RIGHT = 8
const INPUT_BOOST = 16
const INPUT_FIRE = 32
const INPUT_WEAPON_NEXT = 64
const INPUT_WEAPON_PREV = 128

func _ready() -> void:
	# Find GameSettings
	game_settings = get_tree().current_scene.get_node_or_null("GameSettings")
	
	# Set debug mode
	if game_settings:
		debug_mode = game_settings.debug_mode
	
	# Debug component check
	if debug_mode and Engine.has_singleton("Logger"):
		Logger.debug("PlayerShip", "Initializing player ship")
		_log_components()
	
	# Physics setup
	mass = 3.0
	gravity_scale = 0.0
	linear_damp = 0.1
	angular_damp = 2.0
	
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.0
	physics_material_override.bounce = 0.0
	
	# Connect signals
	if health_component:
		health_component.damaged.connect(_on_health_damaged)
		health_component.died.connect(_on_health_died)
	
	# Setup weapon management
	_initialize_weapon_system()
	
	# Set starting position
	if game_settings:
		global_position = game_settings.get_player_starting_position()
		
		if debug_mode and Engine.has_singleton("Logger"):
			Logger.debug("PlayerShip", "Starting at configured position: " + str(global_position))
	
	# Ensure we're in the player group
	add_to_group("player")
	
	if Engine.has_singleton("Logger"):
		Logger.info("PlayerShip", "Player ship initialized and ready")

func _initialize_weapon_system() -> void:
	# Get or create weapon manager component
	weapon_manager = get_node_or_null("WeaponManagerComponent")
	if not weapon_manager:
		weapon_manager = WeaponManagerComponent.new()
		weapon_manager.name = "WeaponManagerComponent"
		add_child(weapon_manager)
	
	# Configure weapon manager
	weapon_manager.auto_initialize = true
	
	# If no specific weapons path is set, search in the player ship
	if weapon_manager.weapons_path.is_empty():
		weapon_manager.weapons_path = NodePath(".")
	
	# Connect to weapon switching signal
	if weapon_manager.has_signal("weapon_switched") and not weapon_manager.is_connected("weapon_switched", _on_weapon_switched):
		weapon_manager.connect("weapon_switched", _on_weapon_switched)
	
	# Give it a chance to initialize
	await get_tree().process_frame
	
	if debug_mode and Engine.has_singleton("Logger"):
		var current_weapon = weapon_manager.get_current_weapon()
		if current_weapon:
			Logger.debug("PlayerShip", "Initial weapon: " + current_weapon.weapon_name)
		else:
			Logger.warning("PlayerShip", "No weapons initialized!")

func _process(_delta: float) -> void:
	# Handle weapon firing
	if input_enabled and _input_state & INPUT_FIRE:
		if weapon_manager:
			weapon_manager.fire()

func _physics_process(_delta: float) -> void:
	if input_enabled:
		_handle_input()
	
	# Apply movement based on input state
	if movement_component and movement_component.enabled:
		# Forward/backward movement
		movement_component.thrust_forward(bool(_input_state & INPUT_FORWARD))
		movement_component.thrust_backward(bool(_input_state & INPUT_BACKWARD))
		
		# Rotation
		if _input_state & INPUT_LEFT:
			movement_component.rotate_left()
		elif _input_state & INPUT_RIGHT:
			movement_component.rotate_right()
		else:
			movement_component.stop_rotation()
		
		# Boost
		if _input_state & INPUT_BOOST:
			movement_component.start_boost()
		else:
			movement_component.stop_boost()

func _handle_input() -> void:
	# Reset input state
	_input_state = 0
	
	# Check each input and set appropriate bits
	if Input.is_action_pressed("move_up") or Input.is_action_pressed("p1_up"):
		_input_state |= INPUT_FORWARD
	
	if Input.is_action_pressed("move_down") or Input.is_action_pressed("p1_down"):
		_input_state |= INPUT_BACKWARD
	
	if Input.is_action_pressed("move_left") or Input.is_action_pressed("p1_left"):
		_input_state |= INPUT_LEFT
	
	if Input.is_action_pressed("move_right") or Input.is_action_pressed("p1_right"):
		_input_state |= INPUT_RIGHT
	
	if Input.is_action_pressed("boost"):
		_input_state |= INPUT_BOOST
	
	if Input.is_action_pressed("p1_primary"):
		_input_state |= INPUT_FIRE
	
	# Handle weapon switching
	if Input.is_action_just_pressed("weapon_next"):
		_input_state |= INPUT_WEAPON_NEXT
		if weapon_manager:
			weapon_manager.next_weapon()
	
	if Input.is_action_just_pressed("weapon_previous"):
		_input_state |= INPUT_WEAPON_PREV
		if weapon_manager:
			weapon_manager.previous_weapon()
	
	# Update state machine based on input
	if state_machine:
		var current_state = state_machine.get_current_state_name()
		
		if current_state in ["DeadState", "DamagedState", "RespawningState"]:
			return
			
		if _input_state & INPUT_FORWARD or _input_state & INPUT_BACKWARD:
			if current_state != "MovingState":
				state_machine.transition_to("moving")
		elif _input_state & INPUT_LEFT or _input_state & INPUT_RIGHT:
			if current_state != "RotatingState":
				state_machine.transition_to("rotating")
		else:
			state_machine.transition_to("idle")

func _on_weapon_switched(old_weapon, new_weapon, _index) -> void:
	if debug_mode and Engine.has_singleton("Logger"):
		var old_name = old_weapon.weapon_name if old_weapon else "None"
		var new_name = new_weapon.weapon_name if new_weapon else "None"
		Logger.debug("PlayerShip", "Switched weapon: " + old_name + " -> " + new_name)
	
	# Emit signal for UI to update
	if new_weapon:
		weapon_switched.emit(new_weapon.weapon_name)
	
	# You could play a weapon switch sound here:
	# if Engine.has_singleton("AudioManager"):
	#     AudioManager.play_sfx("weapon_switch", global_position)

func _on_health_damaged(amount: float, _source: Node) -> void:
	player_damaged.emit(amount)
	
	if debug_mode and Engine.has_singleton("Logger"):
		Logger.debug("PlayerShip", "Player took %s damage" % amount)
	
	# Only transition to damaged state if health is critical
	if health_component and health_component.is_critical() and state_machine:
		state_machine.transition_to("damaged")
		
		# Temporarily disable input
		input_enabled = false
		get_tree().create_timer(0.5).timeout.connect(func(): input_enabled = true)

func _on_health_died() -> void:
	player_died.emit()
	
	if state_machine:
		state_machine.transition_to("dead")
	
	input_enabled = false
	
	if Engine.has_singleton("Logger"):
		Logger.info("PlayerShip", "Player died")

func respawn(spawn_position: Vector2 = Vector2.ZERO) -> void:
	var call_id = -1
	if debug_mode and Engine.has_singleton("Logger"):
		call_id = Logger.debug_method("PlayerShip", "respawn", {
			"spawn_position": spawn_position
		})
	
	# Reset position and physics
	global_position = spawn_position
	linear_velocity = Vector2.ZERO
	angular_velocity = 0
	rotation = 0
	
	# Enable all components
	for child in get_children():
		if child is Component:
			child.enable()
	
	# Restore health
	if health_component:
		health_component.heal(health_component.max_health, null)
	
	# Reset shield
	if shield_component:
		shield_component.current_shield = shield_component.max_shield
		shield_component.shield_changed.emit(shield_component.current_shield, shield_component.max_shield)
	
	# Reset state and input
	if state_machine:
		state_machine.transition_to("idle")
	
	input_enabled = true
	player_respawned.emit()
	
	if debug_mode and Engine.has_singleton("Logger"):
		if call_id >= 0:
			Logger.debug_method_result("PlayerShip", call_id, {
				"position": spawn_position,
				"state": state_machine.get_current_state_name() if state_machine else "unknown"
			})
		else:
			Logger.debug("PlayerShip", "Player respawned at " + str(spawn_position))

func play_death_effect() -> void:
	if debug_mode and Engine.has_singleton("Logger"):
		Logger.debug("PlayerShip", "Playing death effect")
	
	var particles = CPUParticles2D.new()
	
	# Configure particles
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 50
	particles.lifetime = 1.0
	particles.local_coords = false
	particles.direction = Vector2.ZERO
	particles.spread = 180
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 100
	particles.initial_velocity_max = 300
	
	# Create gradient
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1.0, 0.7, 0.3, 1.0))
	gradient.add_point(0.5, Color(1.0, 0.3, 0.1, 0.8))
	gradient.add_point(1.0, Color(0.2, 0.2, 0.2, 0))
	particles.color_ramp = gradient
	
	add_child(particles)
	
	# Auto-cleanup
	get_tree().create_timer(2.0).timeout.connect(particles.queue_free)

func add_upgrade_strategy(strategy, component_name: String) -> bool:
	var component = get_node_or_null(component_name)
	
	if not component or not component is Component:
		if debug_mode and Engine.has_singleton("Logger"):
			Logger.warning("PlayerShip", "Failed to add strategy: component not found: " + component_name)
		return false
	
	strategy.apply_to_component(component)
	
	if debug_mode and Engine.has_singleton("Logger"):
		Logger.debug("PlayerShip", "Added strategy: %s to %s" % [strategy.strategy_name, component_name])
	return true

func remove_upgrade_strategy(strategy) -> void:
	if strategy.owner_component:
		strategy.remove_from_component()
		if debug_mode and Engine.has_singleton("Logger"):
			Logger.debug("PlayerShip", "Removed strategy: %s" % strategy.strategy_name)

func _on_body_entered(body: Node) -> void:
	if not health_component:
		return
	
	if debug_mode and Engine.has_singleton("Logger"):
		Logger.debug("PlayerShip", "Collided with: %s" % body.name)
		
	if body.is_in_group("asteroid"):
		var impact_velocity = linear_velocity.length()
		var damage = impact_velocity * 0.05
		health_component.apply_damage(damage, "collision", body)
		
		if debug_mode and Engine.has_singleton("Logger"):
			Logger.debug("PlayerShip", "Asteroid collision damage: %.1f (velocity: %.1f)" % [damage, impact_velocity])
	
	elif body.is_in_group("enemy"):
		health_component.apply_damage(20.0, "collision", body)
		
		if debug_mode and Engine.has_singleton("Logger"):
			Logger.debug("PlayerShip", "Enemy collision damage: 20.0")

func _log_components() -> void:
	if not debug_mode or not Engine.has_singleton("Logger"):
		return
		
	Logger.debug("PlayerShip", "Components in player ship:")
	for child in get_children():
		if child is Component:
			Logger.debug("PlayerShip", "  - " + child.name + " (" + str(child.get_path()) + ")")

# Get the current weapon for external systems
func get_current_weapon() -> WeaponComponent:
	if weapon_manager:
		return weapon_manager.get_current_weapon()
	return null

# Utility function to get health percentage
func get_health_percent() -> float:
	if health_component:
		return health_component.get_health_percent()
	return 1.0

# Utility function to get shield percentage
func get_shield_percent() -> float:
	if shield_component:
		return shield_component.get_shield_percent()
	return 1.0
