class_name PlayerOne
extends RigidBody2D

# Node references
@onready var health_component = $HealthComponent
@onready var movement_component = $MovementComponent
@onready var combat_component = $CombatComponent
@onready var resource_component = $ResourceComponent
@onready var state_machine = $StateMachine
@onready var health_bar = $HealthBar
@onready var sprite = $Sprite2D
@onready var thruster_particles = $ThrusterParticles
@onready var rotation_helper = $RotationHelper

# Constants
const ROTATION_SPEED = 5.0

# State tracking
var is_immobilized = false
var was_in_boundary_cell = false
var was_outside_grid = false
var respawn_timer = 0.0
var last_valid_position = Vector2.ZERO

# Input tracking
var thrust_input = Vector2.ZERO
var target_angle = 0.0

# Laser hit detection
var hit_radius = 15.0  # For laser collision detection

func _ready():
	# Initialize components if they exist
	if health_component:
		health_component.health_changed.connect(_on_health_changed)
		health_component.health_depleted.connect(_on_health_depleted)
	
	# Fix sprite rotation issue
	if sprite:
		# Add 90 degrees rotation to compensate for sprite orientation
		sprite.rotation_degrees = 90
	
	# Set up particle emitters
	if thruster_particles:
		thruster_particles.emitting = false
	
	# Set initial state
	if state_machine:
		state_machine.initialize()

func _process(delta):
	if is_immobilized:
		return
	
	# Handle thruster particles
	update_thruster_particles()
	
	# Update health bar
	update_health_bar()

func _physics_process(delta):
	if is_immobilized:
		linear_velocity = Vector2.ZERO
		angular_velocity = 0
		return
	
	handle_movement(delta)

func _input(event):
	# Exit early if immobilized
	if is_immobilized:
		return
	
	# Process combat inputs
	if event.is_action_pressed("primary_fire"):
		fire_weapon()
	
	# Handle weapon switching
	if event.is_action_pressed("weapon_next"):
		cycle_weapon(1)
	elif event.is_action_pressed("weapon_prev"):
		cycle_weapon(-1)
	
	# Direct weapon selection
	for i in range(1, 10):
		if event.is_action_pressed("weapon_" + str(i)):
			select_weapon(i - 1)

func handle_movement(delta):
	# Calculate thrust input
	thrust_input = Vector2.ZERO
	
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		thrust_input.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		thrust_input.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		thrust_input.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		thrust_input.x += 1
	
	# Normalize for consistent speed when moving diagonally
	if thrust_input.length_squared() > 0:
		thrust_input = thrust_input.normalized()
	
	# Calculate rotation based on mouse position
	var mouse_pos = get_global_mouse_position()
	var direction = (mouse_pos - global_position).normalized()
	target_angle = direction.angle()
	
	# Handle rotation through rotation helper
	var current_angle = rotation
	var angle_diff = wrapf(target_angle - current_angle, -PI, PI)
	
	if abs(angle_diff) > 0.01:
		var rotation_amount = sign(angle_diff) * min(ROTATION_SPEED * delta, abs(angle_diff))
		rotation += rotation_amount
	
	# Apply thrust through the movement component
	if movement_component:
		movement_component.apply_movement(thrust_input, self)

func update_thruster_particles():
	if thruster_particles:
		# Only emit particles when thrusting
		thruster_particles.emitting = thrust_input.length_squared() > 0
		
		# Set particle direction opposite to thrust
		if thruster_particles.emitting:
			# Point particles in the opposite direction of movement
			var thrust_angle = thrust_input.angle()
			thruster_particles.rotation = thrust_angle + PI  # Add PI to reverse direction
			
			# Adjust particle emission based on thrust intensity
			thruster_particles.amount = int(30 * thrust_input.length())

func update_health_bar():
	if health_bar and health_component:
		var health_percent = health_component.get_health_percent()
		health_bar.size.x = 40 * health_percent
		
		# Update color based on health
		if health_percent > 0.6:
			health_bar.color = Color(0, 0.8, 0, 1)  # Green
		elif health_percent > 0.3:
			health_bar.color = Color(0.9, 0.6, 0, 1)  # Orange
		else:
			health_bar.color = Color(0.9, 0, 0, 1)  # Red

func fire_weapon():
	if combat_component and !is_immobilized:
		combat_component.fire(global_position, rotation, Vector2.from_angle(rotation))

func cycle_weapon(direction):
	if combat_component:
		combat_component.cycle_weapon(direction)

func select_weapon(index):
	if combat_component:
		combat_component.select_weapon(index)

func set_immobilized(value):
	is_immobilized = value
	
	# Update state machine
	if state_machine:
		if is_immobilized:
			state_machine.transition_to("Immobilized")
		else:
			state_machine.transition_to("Normal")
	
	# Stop thruster particles when immobilized
	if thruster_particles:
		thruster_particles.emitting = false

func take_damage(amount):
	if health_component:
		health_component.take_damage(amount)

func check_laser_hit(laser):
	# Simple circle collision check for lasers
	var distance = global_position.distance_to(laser.global_position)
	return distance <= hit_radius

func get_current_weapon_info():
	if combat_component:
		return combat_component.get_current_weapon_info()
	return null

func _on_health_changed(new_health, max_health):
	update_health_bar()

func _on_health_depleted():
	# Trigger explosion
	var explode_component = get_node_or_null("ExplodeFireComponent")
	if explode_component and explode_component.has_method("create_explosion"):
		explode_component.create_explosion(global_position)
	
	# Start player rescue sequence
	set_immobilized(true)
	respawn_timer = 3.0
	
	# Reset the player through the main scene
	var main = get_tree().current_scene
	if main and main.has_method("respawn_player_at_initial_planet"):
		await get_tree().create_timer(2.0).timeout
		main.respawn_player_at_initial_planet()
