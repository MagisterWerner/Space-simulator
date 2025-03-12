# scripts/entities/player_ship.gd
extends RigidBody2D
class_name PlayerShip

signal player_damaged(amount)
signal player_died
signal player_respawned

# Cached component references
@onready var health_component: HealthComponent = $HealthComponent
@onready var movement_component: MovementComponent = $MovementComponent
@onready var shield_component: ShieldComponent = $ShieldComponent
@onready var weapon_component: WeaponComponent = $WeaponComponent
@onready var state_machine: StateMachine = $StateMachine

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

func _ready() -> void:
	# Find GameSettings
	game_settings = get_tree().current_scene.get_node_or_null("GameSettings")
	
	# Set debug mode
	if game_settings:
		debug_mode = game_settings.debug_mode
	
	# Debug component check
	if debug_mode:
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
	
	# Set starting position
	if game_settings:
		global_position = game_settings.get_player_starting_position()
		
		if debug_mode:
			print("[PlayerShip] Starting at configured position: ", global_position)
	
	# Ensure we're in the player group
	add_to_group("player")

func _process(_delta: float) -> void:
	# Handle weapon firing
	if input_enabled and _input_state & INPUT_FIRE and weapon_component:
		weapon_component.fire()

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

func _on_health_damaged(amount: float, _source: Node) -> void:
	player_damaged.emit(amount)
	
	# Only transition to damaged state if health is critical
	if health_component and health_component.is_critical() and state_machine:
		state_machine.transition_to("damaged")
		
		# Temporarily disable input
		input_enabled = false
		get_tree().create_timer(0.5).timeout.connect(func(): input_enabled = true)
	
	if debug_mode:
		print("[PlayerShip] Player took %s damage" % amount)

func _on_health_died() -> void:
	player_died.emit()
	
	if state_machine:
		state_machine.transition_to("dead")
	
	input_enabled = false
	
	if debug_mode:
		print("[PlayerShip] Player died")

func respawn(spawn_position: Vector2 = Vector2.ZERO) -> void:
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
	
	if debug_mode:
		print("[PlayerShip] Player respawned at ", spawn_position)

func play_death_effect() -> void:
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
		if debug_mode:
			print("[PlayerShip] Failed to add strategy: component not found")
		return false
	
	strategy.apply_to_component(component)
	
	if debug_mode:
		print("[PlayerShip] Added strategy: %s to %s" % [strategy.strategy_name, component_name])
	return true

func remove_upgrade_strategy(strategy) -> void:
	if strategy.owner_component:
		strategy.remove_from_component()
		if debug_mode:
			print("[PlayerShip] Removed strategy: %s" % strategy.strategy_name)

func _on_body_entered(body: Node) -> void:
	if not health_component:
		return
		
	if body.is_in_group("asteroid"):
		var impact_velocity = linear_velocity.length()
		var damage = impact_velocity * 0.05
		health_component.apply_damage(damage, "collision", body)
	
	elif body.is_in_group("enemy"):
		health_component.apply_damage(20.0, "collision", body)
	
	if debug_mode:
		print("[PlayerShip] Collided with: %s" % body.name)

func _log_components() -> void:
	print("[PlayerShip] Components in player ship:")
	for child in get_children():
		if child is Component:
			print("[PlayerShip]  - " + child.name + " (" + str(child.get_path()) + ")")
