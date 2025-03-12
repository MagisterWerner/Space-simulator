# scripts/components/movement_component.gd - Optimized implementation
extends Component
class_name MovementComponent

signal thrusting_changed(is_thrusting)
signal boost_activated
signal boost_depleted
signal boost_recharged

@export_category("Movement Properties")
@export var thrust_force: float = 200.0
@export var reverse_force: float = 100.0
@export var rotation_force: float = 300.0
@export var max_speed: float = 700.0
@export var dampening_factor: float = 0.98

@export_category("Boost")
@export var boost_enabled: bool = true
@export var boost_multiplier: float = 2.0
@export var boost_duration: float = 3.0
@export var boost_cooldown: float = 4.0
@export var boost_fuel: float = 100.0
@export var boost_fuel_consumption: float = 30.0
@export var boost_fuel_regen: float = 20.0

# Thruster node paths
@export_category("Thruster Nodes")
@export var main_thruster_path: NodePath = "MainThruster"
@export var left_thruster_rear_path: NodePath = "ThrusterPositions/Left/RearThruster"
@export var left_thruster_front_path: NodePath = "ThrusterPositions/Left/FrontThruster"
@export var right_thruster_rear_path: NodePath = "ThrusterPositions/Right/RearThruster"
@export var right_thruster_front_path: NodePath = "ThrusterPositions/Right/FrontThruster"
@export var left_position_path: NodePath = "ThrusterPositions/Left"
@export var right_position_path: NodePath = "ThrusterPositions/Right"

@export_category("Audio")
@export var enable_audio: bool = true
@export var main_thruster_sound_name: String = "thruster"
@export var rotation_thruster_sound_name: String = "thruster"
@export var backward_thruster_sound_name: String = "thruster"
@export var boost_sound_name: String = "boost"
@export var main_thruster_volume_db: float = 0.0
@export var rotation_thruster_volume_db: float = -6.0
@export var backward_thruster_volume_db: float = -3.0
@export var main_thruster_pitch: float = 1.0
@export var rotation_thruster_pitch: float = 1.1
@export var backward_thruster_pitch: float = 0.9

# Movement state
var _is_thrusting_forward: bool = false
var _is_thrusting_backward: bool = false
var _rotation_direction: float = 0.0
var _is_boosting: bool = false
var _boost_cooldown_remaining: float = 0.0
var _current_boost_fuel: float = 100.0

# References
var _rigid_body: RigidBody2D
var _movement_strategies: Array = []
var _audio_manager = null

# Thruster nodes
var _main_thruster: Node
var _left_thruster_rear: Node
var _left_thruster_front: Node
var _right_thruster_rear: Node
var _right_thruster_front: Node
var _left_position: Node2D
var _right_position: Node2D

# Audio players
var _main_thruster_player = null
var _rotation_thruster_player = null
var _backward_thruster_player = null
var _boost_thruster_player = null
var _main_thruster_active: bool = false
var _rotation_thruster_active: bool = false
var _backward_thruster_active: bool = false
var _boost_sound_active: bool = false

# Performance optimizations
var _cached_direction_right: Vector2 = Vector2.RIGHT
var _cached_direction_left: Vector2 = Vector2.LEFT
var _thrust_modified: bool = false
var _rotation_modified: bool = false
var _max_speed_modified: bool = false

func setup() -> void:
	if owner_entity is RigidBody2D:
		_rigid_body = owner_entity
	else:
		push_error("MovementComponent: Owner is not a RigidBody2D")
		disable()
		return
	
	_current_boost_fuel = boost_fuel
	
	# Find thruster nodes - simplified search
	_find_thruster_nodes()
	
	# Setup audio
	if enable_audio:
		_audio_manager = get_node_or_null("/root/AudioManager")
		if _audio_manager == null:
			enable_audio = false
			push_warning("MovementComponent: AudioManager not found, disabling audio")
	
	if debug_mode:
		_debug_print("Movement component setup complete")

func _find_thruster_nodes() -> void:
	# Direct paths first
	_main_thruster = get_node_or_null(main_thruster_path)
	_left_thruster_rear = get_node_or_null(left_thruster_rear_path)
	_left_thruster_front = get_node_or_null(left_thruster_front_path)
	_right_thruster_rear = get_node_or_null(right_thruster_rear_path)
	_right_thruster_front = get_node_or_null(right_thruster_front_path)
	_left_position = get_node_or_null(left_position_path)
	_right_position = get_node_or_null(right_position_path)
	
	# Fallbacks for critical nodes
	if _main_thruster == null:
		_main_thruster = owner_entity.find_child("MainThruster", true, false)
	
	# Only log in debug mode
	if debug_mode:
		_debug_print("Thrusters found: Main=" + str(_main_thruster != null) + 
				", LR=" + str(_left_thruster_rear != null) + 
				", LF=" + str(_left_thruster_front != null) + 
				", RR=" + str(_right_thruster_rear != null) + 
				", RF=" + str(_right_thruster_front != null))

func _on_enable() -> void:
	# Resume audio if it was playing
	if enable_audio:
		if _is_thrusting_forward:
			_start_main_thruster_sound()
		if _rotation_direction != 0:
			_start_rotation_thruster_sound()
		if _is_thrusting_backward:
			_start_backward_thruster_sound()
		if _is_boosting:
			_start_boost_sound()

func _on_disable() -> void:
	# Stop all audio when component is disabled
	if enable_audio:
		_stop_all_thruster_sounds()

func physics_process_component(delta: float) -> void:
	if not _rigid_body or not enabled:
		return
	
	# Initialize with base values
	var modified_thrust = thrust_force
	var modified_reverse = reverse_force
	var modified_rotation = rotation_force
	var modified_max_speed = max_speed
	
	# Apply strategy modifications - only if we have strategies
	if not _movement_strategies.is_empty():
		for strategy in _movement_strategies:
			if strategy.has_method("modify_thrust"):
				modified_thrust = strategy.modify_thrust(modified_thrust)
			if strategy.has_method("modify_reverse_thrust"):
				modified_reverse = strategy.modify_reverse_thrust(modified_reverse)
			if strategy.has_method("modify_rotation"):
				modified_rotation = strategy.modify_rotation(modified_rotation)
			if strategy.has_method("modify_max_speed"):
				modified_max_speed = strategy.modify_max_speed(modified_max_speed)
	
	# Apply boost
	if _is_boosting:
		modified_thrust *= boost_multiplier
		modified_reverse *= boost_multiplier
		
		# Handle boost fuel consumption
		_current_boost_fuel -= boost_fuel_consumption * delta
		if _current_boost_fuel <= 0:
			_current_boost_fuel = 0
			stop_boost()
			boost_depleted.emit()
	elif boost_enabled and _current_boost_fuel < boost_fuel:
		# Regenerate boost fuel when not boosting
		_current_boost_fuel = min(_current_boost_fuel + (boost_fuel_regen * delta), boost_fuel)
		
		# Signal when fully recharged
		if _current_boost_fuel >= boost_fuel and _boost_cooldown_remaining <= 0:
			_current_boost_fuel = boost_fuel
			boost_recharged.emit()
	
	# Update boost cooldown
	if _boost_cooldown_remaining > 0:
		_boost_cooldown_remaining -= delta
	
	# Update rotation cached values
	var rotation = _rigid_body.rotation
	_cached_direction_right = Vector2.RIGHT.rotated(rotation)
	_cached_direction_left = Vector2.LEFT.rotated(rotation)
	
	# Handle forward thrust
	if _is_thrusting_forward:
		_rigid_body.apply_central_force(_cached_direction_right * modified_thrust)
		_set_thruster_emission(_main_thruster, true)
	else:
		_set_thruster_emission(_main_thruster, false)
	
	# Handle backward movement
	if _is_thrusting_backward:
		_rigid_body.apply_central_force(_cached_direction_left * modified_reverse)
		
		# Audio management
		if enable_audio and not _backward_thruster_active:
			_start_backward_thruster_sound()
		
		# Turning while moving backward
		if _rotation_direction > 0:  # Turn right while moving backward
			_set_thruster_emission(_right_thruster_front, true)
			_set_thruster_emission(_left_thruster_front, false)
			
			if _right_position:
				_rigid_body.apply_torque(modified_rotation * 0.3)
			
		elif _rotation_direction < 0:  # Turn left while moving backward
			_set_thruster_emission(_left_thruster_front, true)
			_set_thruster_emission(_right_thruster_front, false)
			
			if _left_position:
				_rigid_body.apply_torque(-modified_rotation * 0.3)
			
		else:  # Just moving backward without turning
			_set_thruster_emission(_left_thruster_front, true)
			_set_thruster_emission(_right_thruster_front, true)
	else:
		_set_thruster_emission(_left_thruster_front, false)
		_set_thruster_emission(_right_thruster_front, false)
		
		# Stop audio
		if _backward_thruster_active:
			_stop_backward_thruster_sound()
	
	# Handle rotation while not moving backward
	if not _is_thrusting_backward:
		if _rotation_direction > 0:  # Turn right
			_set_thruster_emission(_left_thruster_rear, true)
			_rigid_body.apply_torque(modified_rotation)
		else:
			_set_thruster_emission(_left_thruster_rear, false)
		
		if _rotation_direction < 0:  # Turn left
			_set_thruster_emission(_right_thruster_rear, true)
			_rigid_body.apply_torque(-modified_rotation)
		else:
			_set_thruster_emission(_right_thruster_rear, false)
	
	# Cap maximum speed
	var speed = _rigid_body.linear_velocity.length()
	if speed > modified_max_speed:
		_rigid_body.linear_velocity = _rigid_body.linear_velocity.normalized() * modified_max_speed
	
	# Apply dampening
	_rigid_body.linear_velocity *= dampening_factor
	
	# Update audio positions
	if enable_audio:
		_update_audio_positions()

func _update_audio_positions() -> void:
	var pos = owner_entity.global_position
	
	# Update position for active sound players
	if _main_thruster_active and _main_thruster_player:
		_main_thruster_player.global_position = pos
	
	if _rotation_thruster_active and _rotation_thruster_player:
		_rotation_thruster_player.global_position = pos
		
	if _backward_thruster_active and _backward_thruster_player:
		_backward_thruster_player.global_position = pos
		
	if _boost_sound_active and _boost_thruster_player:
		_boost_thruster_player.global_position = pos

func thrust_forward(activate: bool = true) -> void:
	if _is_thrusting_forward == activate:
		return
		
	_is_thrusting_forward = activate
	
	if enable_audio:
		if _is_thrusting_forward:
			_start_main_thruster_sound()
		else:
			_stop_main_thruster_sound()
	
	thrusting_changed.emit(_is_thrusting_forward)

func thrust_backward(activate: bool = true) -> void:
	_is_thrusting_backward = activate

func rotate_left() -> void:
	var was_rotating = _rotation_direction != 0
	_rotation_direction = -1.0
	
	if enable_audio and not was_rotating:
		_start_rotation_thruster_sound()

func rotate_right() -> void:
	var was_rotating = _rotation_direction != 0
	_rotation_direction = 1.0
	
	if enable_audio and not was_rotating:
		_start_rotation_thruster_sound()

func stop_rotation() -> void:
	var was_rotating = _rotation_direction != 0
	_rotation_direction = 0.0
	
	if enable_audio and was_rotating:
		_stop_rotation_thruster_sound()

func start_boost() -> void:
	if not boost_enabled or _is_boosting or _boost_cooldown_remaining > 0 or _current_boost_fuel <= 0:
		return
	
	_is_boosting = true
	
	if enable_audio:
		_start_boost_sound()
		
	boost_activated.emit()
	
	if debug_mode:
		_debug_print("Boost activated")

func stop_boost() -> void:
	if not _is_boosting:
		return
	
	_is_boosting = false
	_boost_cooldown_remaining = boost_cooldown
	
	if enable_audio:
		_stop_boost_sound()
		
	if debug_mode:
		_debug_print("Boost stopped")

# Simplified audio methods
func _start_main_thruster_sound() -> void:
	if _main_thruster_active or _audio_manager == null:
		return
	
	_main_thruster_active = true
	
	_main_thruster_player = _audio_manager.play_sfx(
		main_thruster_sound_name, 
		owner_entity.global_position, 
		main_thruster_pitch, 
		main_thruster_volume_db
	)

func _stop_main_thruster_sound() -> void:
	if not _main_thruster_active:
		return
	
	_main_thruster_active = false
	
	if _main_thruster_player:
		_main_thruster_player.stop()
		_main_thruster_player = null

func _start_rotation_thruster_sound() -> void:
	if _rotation_thruster_active or _audio_manager == null:
		return
	
	_rotation_thruster_active = true
	
	_rotation_thruster_player = _audio_manager.play_sfx(
		rotation_thruster_sound_name, 
		owner_entity.global_position, 
		rotation_thruster_pitch,
		rotation_thruster_volume_db
	)

func _stop_rotation_thruster_sound() -> void:
	if not _rotation_thruster_active:
		return
	
	_rotation_thruster_active = false
	
	if _rotation_thruster_player:
		_rotation_thruster_player.stop()
		_rotation_thruster_player = null

func _start_backward_thruster_sound() -> void:
	if _backward_thruster_active or _audio_manager == null:
		return
	
	_backward_thruster_active = true
	
	_backward_thruster_player = _audio_manager.play_sfx(
		backward_thruster_sound_name, 
		owner_entity.global_position, 
		backward_thruster_pitch,
		backward_thruster_volume_db
	)

func _stop_backward_thruster_sound() -> void:
	if not _backward_thruster_active:
		return
	
	_backward_thruster_active = false
	
	if _backward_thruster_player:
		_backward_thruster_player.stop()
		_backward_thruster_player = null

func _start_boost_sound() -> void:
	if _boost_sound_active or _audio_manager == null:
		return
	
	_boost_sound_active = true
	
	_boost_thruster_player = _audio_manager.play_sfx(
		boost_sound_name, 
		owner_entity.global_position, 
		0.9,
		0.0
	)

func _stop_boost_sound() -> void:
	if not _boost_sound_active:
		return
	
	_boost_sound_active = false
	
	if _boost_thruster_player:
		_boost_thruster_player.stop()
		_boost_thruster_player = null

func _stop_all_thruster_sounds() -> void:
	_stop_main_thruster_sound()
	_stop_rotation_thruster_sound()
	_stop_backward_thruster_sound()
	_stop_boost_sound()

# Helper for thruster effects
func _set_thruster_emission(thruster: Node, emitting: bool) -> void:
	if thruster == null:
		return
		
	if thruster is CPUParticles2D or thruster is GPUParticles2D:
		thruster.emitting = emitting
	elif thruster is Node2D:
		thruster.visible = emitting

# Public utility methods
func get_boost_fuel_percent() -> float:
	return _current_boost_fuel / boost_fuel

func get_current_velocity() -> Vector2:
	return _rigid_body.linear_velocity if _rigid_body else Vector2.ZERO

func get_current_speed() -> float:
	return _rigid_body.linear_velocity.length() if _rigid_body else 0.0

func add_movement_strategy(strategy) -> void:
	if not _movement_strategies.has(strategy):
		_movement_strategies.append(strategy)
		
func remove_movement_strategy(strategy) -> void:
	_movement_strategies.erase(strategy)
