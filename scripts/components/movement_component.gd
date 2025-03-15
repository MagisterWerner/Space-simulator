extends Component
class_name MovementComponent

# Movement signals
signal thrust_changed(level)
signal rotation_changed(direction)
signal boost_activated(is_active)
signal velocity_changed(speed)

# Basic movement properties
@export_group("Basic Movement")
@export var max_speed: float = 400.0
@export var acceleration: float = 12.0
@export var deceleration: float = 4.0
@export var rotation_speed: float = 3.0

# Advanced movement properties
@export_group("Advanced Movement")
@export var drift_factor: float = 0.92
@export var can_boost: bool = true
@export var boost_multiplier: float = 1.5
@export var boost_duration: float = 3.0
@export var boost_cooldown: float = 5.0
@export var boost_fuel_cost: float = 5.0

# Fuel system properties
@export_group("Fuel System")
@export var use_fuel: bool = true
@export var fuel_consumption_rate: float = 1.0  # Fuel units per second
@export var fuel_consumption_modifier: float = 1.0
@export var min_speed_factor: float = 0.3  # Minimum speed percentage when out of fuel

# Debug properties
@export_group("Debug")
@export var show_force_gizmos: bool = false

# Current state
var current_speed: float = 0.0
var current_rotation: float = 0.0
var is_thrusting_forward: bool = false
var is_thrusting_backward: bool = false
var is_rotating_left: bool = false
var is_rotating_right: bool = false
var is_boosting: bool = false
var thrust_level: float = 0.0
var rotation_direction: float = 0.0

# Boost state
var boost_remaining: float = 0.0
var boost_cooldown_remaining: float = 0.0
var can_activate_boost: bool = true

# Entity references
var owner_entity = null
var _resource_manager = null
var _audio_manager = null
var _effect_manager = null

# Particle effects
var _thrust_particles = null
var _boost_particles = null

# Sound effects
var _thrust_sound_instance = null
var _is_thrust_sound_playing: bool = false

func _ready() -> void:
	super._ready()
	
	# Find our owner entity (the ship)
	owner_entity = _find_owner_entity()
	
	# Get manager references
	_resource_manager = get_node_or_null("/root/ResourceManager")
	_audio_manager = get_node_or_null("/root/AudioManager")
	_effect_manager = get_node_or_null("/root/EffectPoolManager")
	
	# Find particle effect nodes
	_thrust_particles = get_node_or_null("ThrustParticles")
	_boost_particles = get_node_or_null("BoostParticles")
	
	# Initialize boost
	boost_remaining = boost_duration
	
	# Set component name
	if component_name.is_empty():
		component_name = "MovementComponent"

func _process(delta: float) -> void:
	if not enabled:
		_stop_thrust_effects()
		return
	
	# Apply rotation
	_apply_rotation(delta)
	
	# Apply thrust
	_apply_thrust(delta)
	
	# Update boost state
	_update_boost_state(delta)
	
	# Update thrust effects
	_update_thrust_effects()

func _physics_process(delta: float) -> void:
	if not enabled or not owner_entity:
		return
	
	# Get final velocity from owner
	if owner_entity is RigidBody2D:
		var speed = owner_entity.linear_velocity.length()
		# Only emit signal when speed changes significantly
		if abs(speed - current_speed) > 1.0:
			current_speed = speed
			velocity_changed.emit(current_speed)

# Apply rotation based on current rotation direction
func _apply_rotation(delta: float) -> void:
	if not owner_entity:
		return
		
	if rotation_direction != 0:
		var rotation_amount = rotation_direction * rotation_speed * delta
		
		if owner_entity is RigidBody2D:
			owner_entity.angular_velocity = rotation_direction * rotation_speed
		else:
			owner_entity.rotation += rotation_amount
		
		current_rotation = rotation_amount / delta

# Apply thrust based on current thrust level
func _apply_thrust(delta: float) -> void:
	if not owner_entity:
		return
	
	var final_thrust = thrust_level
	var has_fuel = true
	
	# Check fuel if using fuel system
	if use_fuel and _resource_manager:
		var fuel_cost = final_thrust * fuel_consumption_rate * fuel_consumption_modifier * delta
		
		if is_boosting:
			fuel_cost *= boost_multiplier
		
		# Skip if no fuel consumption
		if fuel_cost > 0:
			var current_fuel = _resource_manager.get_resource_amount(_resource_manager.ResourceType.FUEL)
			
			if current_fuel <= 0:
				has_fuel = false
				final_thrust *= min_speed_factor
			else:
				_resource_manager.remove_resource(_resource_manager.ResourceType.FUEL, fuel_cost)
	
	# Apply thrust force
	if final_thrust != 0 and owner_entity is RigidBody2D:
		var thrust_direction = Vector2(cos(owner_entity.rotation), sin(owner_entity.rotation))
		var thrust_force = thrust_direction * final_thrust * acceleration
		
		if is_boosting and has_fuel:
			thrust_force *= boost_multiplier
		
		owner_entity.apply_central_force(thrust_force)
	elif final_thrust != 0 and "velocity" in owner_entity:
		# For KinematicBody2D or other entities with direct velocity control
		var thrust_direction = Vector2(cos(owner_entity.rotation), sin(owner_entity.rotation))
		var accel = acceleration * delta
		
		if is_boosting and has_fuel:
			accel *= boost_multiplier
		
		owner_entity.velocity += thrust_direction * final_thrust * accel

# Update boost state
func _update_boost_state(delta: float) -> void:
	# Skip if boost not enabled
	if not can_boost:
		return
	
	# Handle boost cooldown
	if not can_activate_boost and boost_cooldown_remaining > 0:
		boost_cooldown_remaining -= delta
		if boost_cooldown_remaining <= 0:
			can_activate_boost = true
			boost_remaining = boost_duration
	
	# Handle active boost
	if is_boosting:
		boost_remaining -= delta
		if boost_remaining <= 0:
			stop_boost()
			# Start cooldown
			can_activate_boost = false
			boost_cooldown_remaining = boost_cooldown

# Update thrust particle effects and sounds
func _update_thrust_effects() -> void:
	# Update particle effects
	if _thrust_particles:
		_thrust_particles.emitting = thrust_level != 0
		
		if _thrust_particles.emitting:
			# Adjust particle intensity based on thrust
			_thrust_particles.amount = 16 + int(abs(thrust_level) * 16)
			_thrust_particles.initial_velocity_min = 20 + abs(thrust_level) * 20
			_thrust_particles.initial_velocity_max = 40 + abs(thrust_level) * 60
	
	if _boost_particles:
		_boost_particles.emitting = is_boosting and thrust_level != 0
	
	# Update sound effects
	if _audio_manager:
		if thrust_level != 0:
			if not _is_thrust_sound_playing:
				_start_thrust_sound()
		else:
			_stop_thrust_sound()

# Start thrust sound
func _start_thrust_sound() -> void:
	if not _audio_manager or _is_thrust_sound_playing:
		return
	
	_thrust_sound_instance = _audio_manager.play_sfx("thruster", _get_global_position())
	_is_thrust_sound_playing = true

# Stop thrust sound
func _stop_thrust_sound() -> void:
	if not _audio_manager or not _is_thrust_sound_playing:
		return
	
	_is_thrust_sound_playing = false
	
	# If audio manager has a stop method, use it
	if _audio_manager.has_method("stop_sfx"):
		_audio_manager.stop_sfx("thruster")

# Stop all thrust effects
func _stop_thrust_effects() -> void:
	if _thrust_particles:
		_thrust_particles.emitting = false
	
	if _boost_particles:
		_boost_particles.emitting = false
	
	_stop_thrust_sound()

# Find the owner entity (ship)
func _find_owner_entity() -> Node:
	var parent = get_parent()
	# Search up the tree for a RigidBody2D or a node in the player or ships group
	while parent and not parent is RigidBody2D and not parent.is_in_group("player") and not parent.is_in_group("ships"):
		parent = parent.get_parent()
	
	return parent

# PUBLIC API METHODS

# Activate forward thrust
func thrust_forward(active: bool = true) -> void:
	is_thrusting_forward = active
	_update_thrust_level()

# Activate backward thrust
func thrust_backward(active: bool = true) -> void:
	is_thrusting_backward = active
	_update_thrust_level()

# Update the thrust level based on input state
func _update_thrust_level() -> void:
	var new_thrust_level = 0.0
	
	if is_thrusting_forward:
		new_thrust_level += 1.0
	
	if is_thrusting_backward:
		new_thrust_level -= 0.5  # Backward thrust is weaker
	
	# Only emit signal if thrust level changed
	if new_thrust_level != thrust_level:
		thrust_level = new_thrust_level
		thrust_changed.emit(thrust_level)

# Rotate left
func rotate_left() -> void:
	is_rotating_left = true
	is_rotating_right = false
	rotation_direction = 1.0
	rotation_changed.emit(rotation_direction)

# Rotate right
func rotate_right() -> void:
	is_rotating_left = false
	is_rotating_right = true 
	rotation_direction = -1.0
	rotation_changed.emit(rotation_direction)

# Stop rotation
func stop_rotation() -> void:
	is_rotating_left = false
	is_rotating_right = false
	rotation_direction = 0.0
	
	# Stop angular velocity on the physics body
	if owner_entity is RigidBody2D:
		owner_entity.angular_velocity = 0
	
	rotation_changed.emit(rotation_direction)

# Start boost
func start_boost() -> void:
	if not can_boost or not can_activate_boost or is_boosting:
		return
	
	is_boosting = true
	boost_activated.emit(true)
	
	# Play boost sound if available
	if _audio_manager:
		_audio_manager.play_sfx("boost", _get_global_position())
	
	# Create boost effect if available
	if _effect_manager and _effect_manager.has_method("play_effect"):
		_effect_manager.play_effect("boost", _get_global_position(), owner_entity.rotation)

# Stop boost
func stop_boost() -> void:
	if not is_boosting:
		return
	
	is_boosting = false
	boost_activated.emit(false)

# Get the global position from the owner entity
func _get_global_position() -> Vector2:
	if owner_entity and "global_position" in owner_entity:
		return owner_entity.global_position
	return Vector2.ZERO

# Get current velocity
func get_velocity() -> Vector2:
	if owner_entity is RigidBody2D:
		return owner_entity.linear_velocity
	elif "velocity" in owner_entity:
		return owner_entity.velocity
	return Vector2.ZERO

# Get current speed
func get_speed() -> float:
	return current_speed

# Get boost remaining percentage
func get_boost_percent() -> float:
	if can_boost:
		return boost_remaining / boost_duration
	return 0.0

# Get boost cooldown percentage
func get_boost_cooldown_percent() -> float:
	if can_boost and not can_activate_boost:
		return 1.0 - (boost_cooldown_remaining / boost_cooldown)
	return 1.0
