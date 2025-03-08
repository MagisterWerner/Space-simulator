# scripts/entities/player_ship.gd
# Player ship controller that ties together all ship components and handles input
# Updated to integrate with GameSettings
extends RigidBody2D
class_name PlayerShip

signal player_damaged(amount)
signal player_died
signal player_respawned

# Core Components
@onready var health_component: HealthComponent = $HealthComponent
@onready var movement_component: MovementComponent = $MovementComponent
@onready var shield_component: ShieldComponent = $ShieldComponent
@onready var weapon_component: WeaponComponent = $WeaponComponent
@onready var state_machine: StateMachine = $StateMachine

# Debug properties
@export var debug_mode: bool = false
@export var input_enabled: bool = true

# Reference to GameSettings
var game_settings: GameSettings = null

# Input state tracking
var _input_thrust_forward: bool = false
var _input_thrust_backward: bool = false
var _input_rotate_left: bool = false
var _input_rotate_right: bool = false
var _input_boost: bool = false
var _input_fire: bool = false

func _ready() -> void:
	# Find GameSettings in the main scene
	var main_scene = get_tree().current_scene
	game_settings = main_scene.get_node_or_null("GameSettings")
	
	# Set debug mode from settings if available
	if game_settings:
		debug_mode = game_settings.debug_mode
	
	# Debug - print all components to check for duplicates
	if debug_mode:
		debug_print("Components in player ship:")
		for child in get_children():
			if child is Component:
				debug_print(" - " + child.name + " (" + str(child.get_path()) + ")")
	
	# Set optimal physics properties for responsive ship controls
	mass = 3.0
	gravity_scale = 0.0
	linear_damp = 0.1   # Very light damping for space-like movement
	angular_damp = 2.0  # Stronger damping to prevent excessive rotation
	
	# Ensure the ship is set to be a CHARACTER physics for accurate movement
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.0 # No friction
	physics_material_override.bounce = 0.0   # No bounce
	
	# Make sure the rotation is aligned with the sprite (pointing right)
	# The ship sprite should be pointing right (0 degrees rotation)
	# We'll verify and correct the rotation if needed
	for child in get_children():
		if child is Sprite2D:
			# Ensure sprite is oriented with ship pointing to the right 
			# This matches our movement logic
			if abs(child.rotation) > 0.1:
				debug_print("Warning: Sprite rotation doesn't match expected orientation (right-pointing)")
	
	# Connect component signals
	if health_component:
		health_component.damaged.connect(_on_health_damaged)
		health_component.died.connect(_on_health_died)
	
	# Position the ship if requested by game settings
	if game_settings:
		global_position = game_settings.get_player_starting_position()
		
		if debug_mode:
			debug_print("Starting at configured position: " + str(global_position))
	
	# Ensure we're in the player group
	if not is_in_group("player"):
		add_to_group("player")

func _process(_delta: float) -> void:
	# Non-physics updates, like weapon firing
	if input_enabled and _input_fire and weapon_component:
		weapon_component.fire()

func _physics_process(_delta: float) -> void:
	# Handle input and update movement component
	if input_enabled:
		_handle_input()
	
	# Apply inputs to movement component
	if movement_component and movement_component.enabled:
		movement_component.thrust_forward(_input_thrust_forward)
		movement_component.thrust_backward(_input_thrust_backward)
		
		if _input_rotate_left:
			movement_component.rotate_left()
		elif _input_rotate_right:
			movement_component.rotate_right()
		else:
			movement_component.stop_rotation()
			
		if _input_boost:
			movement_component.start_boost()
		else:
			movement_component.stop_boost()

func _handle_input() -> void:
	# Read input state - UP is forward, DOWN is backward
	# Remember in a top-down game: 
	# - FORWARD means moving in the direction the ship is pointing (RIGHT at 0 rotation)
	# - BACKWARD means moving opposite to the ship's pointing direction
	_input_thrust_forward = Input.is_action_pressed("move_up") or Input.is_action_pressed("p1_up")
	_input_thrust_backward = Input.is_action_pressed("move_down") or Input.is_action_pressed("p1_down")
	_input_rotate_left = Input.is_action_pressed("move_left") or Input.is_action_pressed("p1_left")
	_input_rotate_right = Input.is_action_pressed("move_right") or Input.is_action_pressed("p1_right")
	_input_boost = Input.is_action_pressed("boost")
	_input_fire = Input.is_action_pressed("p1_primary")
	
	# Update state machine based on input
	if state_machine:
		if _input_thrust_forward or _input_thrust_backward:
			if state_machine.get_current_state_name() != "MovingState":
				state_machine.transition_to("moving")
		elif _input_rotate_left or _input_rotate_right:
			if state_machine.get_current_state_name() != "RotatingState":
				state_machine.transition_to("rotating")
		elif state_machine.get_current_state_name() not in ["DeadState", "DamagedState", "RespawningState"]:
			state_machine.transition_to("idle")

func _on_health_damaged(amount: float, _source: Node) -> void:
	# Emit player damaged signal
	player_damaged.emit(amount)
	
	# Change state to damaged if health is low
	if health_component and health_component.is_critical() and state_machine:
		state_machine.transition_to("damaged")
		
		# Temporarily disable input during damaged state
		input_enabled = false
		await get_tree().create_timer(0.5).timeout
		input_enabled = true
	
	debug_print("Player took %s damage" % amount)

func _on_health_died() -> void:
	# Emit player died signal
	player_died.emit()
	
	# Change state to dead
	if state_machine:
		state_machine.transition_to("dead")
	
	# Disable input when dead
	input_enabled = false
	
	debug_print("Player died")

func respawn(spawn_position: Vector2 = Vector2.ZERO) -> void:
	# Reset position
	global_position = spawn_position
	
	# Reset physics state
	linear_velocity = Vector2.ZERO
	angular_velocity = 0
	rotation = 0  # Reset rotation to 0 (ship pointing right)
	
	# Enable components
	for child in get_children():
		if child is Component:
			child.enable()
	
	# Heal the ship
	if health_component:
		health_component.heal(health_component.max_health, null)
	
	# Reset shield
	if shield_component:
		shield_component.current_shield = shield_component.max_shield
		shield_component.shield_changed.emit(shield_component.current_shield, shield_component.max_shield)
	
	# Change state to idle
	if state_machine:
		state_machine.transition_to("idle")
	
	# Re-enable input
	input_enabled = true
	
	# Emit player respawned signal
	player_respawned.emit()
	
	debug_print("Player respawned at " + str(global_position))

func play_death_effect() -> void:
	# Optional: Implement death effect here
	# Example: exploding particles
	var explosion_particles = CPUParticles2D.new()
	explosion_particles.emitting = true
	explosion_particles.one_shot = true
	explosion_particles.explosiveness = 1.0
	explosion_particles.amount = 50
	explosion_particles.lifetime = 1.0
	explosion_particles.direction = Vector2.ZERO
	explosion_particles.spread = 180
	explosion_particles.gravity = Vector2.ZERO
	explosion_particles.initial_velocity_min = 100
	explosion_particles.initial_velocity_max = 300
	
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1.0, 0.7, 0.3, 1.0))
	gradient.add_point(0.5, Color(1.0, 0.3, 0.1, 0.8))
	gradient.add_point(1.0, Color(0.2, 0.2, 0.2, 0))
	explosion_particles.color_ramp = gradient
	
	add_child(explosion_particles)
	
	# Auto-remove after particles finish
	var timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = 2.0
	timer.timeout.connect(func(): explosion_particles.queue_free())
	explosion_particles.add_child(timer)
	timer.start()

# Strategy application
func add_upgrade_strategy(strategy, component_name: String) -> bool:
	var component = get_node_or_null(component_name)
	
	if not component or not component is Component:
		debug_print("Failed to add strategy: component not found")
		return false
	
	# Apply the strategy to the component
	strategy.apply_to_component(component)
	
	debug_print("Added strategy: %s to %s" % [strategy.strategy_name, component_name])
	return true

func remove_upgrade_strategy(strategy) -> void:
	if strategy.owner_component:
		strategy.remove_from_component()
		debug_print("Removed strategy: %s" % strategy.strategy_name)

func _on_body_entered(body: Node) -> void:
	# Handle collision with other bodies
	if body.is_in_group("asteroid"):
		# Take collision damage from asteroids
		if health_component:
			var impact_velocity = linear_velocity.length()
			var damage = impact_velocity * 0.05  # Scale damage based on impact velocity
			health_component.apply_damage(damage, "collision", body)
	
	elif body.is_in_group("enemy"):
		# Take collision damage from enemies
		if health_component:
			health_component.apply_damage(20.0, "collision", body)
	
	debug_print("Collided with: %s" % body.name)

func debug_print(message: String) -> void:
	if debug_mode:
		print("[PlayerShip] %s" % message)
