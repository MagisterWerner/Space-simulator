# scripts/components/movement_component.gd - Highly optimized implementation
extends Component
class_name MovementComponent

signal thrusting_changed(is_thrusting)
signal boost_activated
signal boost_depleted
signal boost_recharged

# Movement properties
@export_category("Movement Properties")
@export var thrust_force: float = 200.0
@export var reverse_force: float = 100.0
@export var rotation_force: float = 300.0
@export var max_speed: float = 700.0
@export var dampening_factor: float = 0.98

# Boost properties
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

# Audio properties - compressed into single category
@export_category("Audio")
@export var enable_audio: bool = true
@export var main_thruster_sound_name: String = "thruster"
@export var main_thruster_volume_db: float = 0.0
@export var rotation_thruster_volume_db: float = -6.0
@export var backward_thruster_volume_db: float = -3.0
@export var boost_sound_name: String = "boost"

# Input state - using bitflags for better performance
const INPUT_FORWARD = 1
const INPUT_BACKWARD = 2
const INPUT_LEFT = 4
const INPUT_RIGHT = 8
const INPUT_BOOST = 16

# Cached references
var _rigid_body: RigidBody2D
var _input_state: int = 0
var _movement_strategies: Array = []
var _audio_manager = null

# Thruster nodes - cached on setup
var _main_thruster: Node
var _left_thruster_rear: Node
var _left_thruster_front: Node
var _right_thruster_rear: Node
var _right_thruster_front: Node

# Boost state
var _is_boosting: bool = false
var _boost_cooldown_remaining: float = 0.0
var _current_boost_fuel: float = 100.0

# Audio player references
var _main_thruster_player = null
var _rotation_thruster_player = null
var _backward_thruster_player = null
var _boost_thruster_player = null

# Audio state tracking
var _main_thruster_active: bool = false
var _rotation_thruster_active: bool = false
var _backward_thruster_active: bool = false
var _boost_sound_active: bool = false

# Performance optimizations
var _cached_direction_right: Vector2 = Vector2.RIGHT
var _cached_direction_left: Vector2 = Vector2.LEFT
var _last_rotation: float = 0.0

func setup() -> void:
	if not owner is RigidBody2D:
		disable()
		return
	
	_rigid_body = owner
	_current_boost_fuel = boost_fuel
	
	# Cache thruster nodes
	_main_thruster = get_node_or_null(main_thruster_path)
	_left_thruster_rear = get_node_or_null(left_thruster_rear_path)
	_left_thruster_front = get_node_or_null(left_thruster_front_path)
	_right_thruster_rear = get_node_or_null(right_thruster_rear_path)
	_right_thruster_front = get_node_or_null(right_thruster_front_path)
	
	# Cache audio manager reference
	if enable_audio:
		_audio_manager = get_node_or_null("/root/AudioManager")
		if _audio_manager == null:
			enable_audio = false
	
	# Precalculate direction vectors
	_update_direction_vectors()

func _on_enable() -> void:
	if enable_audio:
		if _input_state & INPUT_FORWARD:
			_start_main_thruster_sound()
		if _input_state & (INPUT_LEFT | INPUT_RIGHT):
			_start_rotation_thruster_sound()
		if _input_state & INPUT_BACKWARD:
			_start_backward_thruster_sound()
		if _is_boosting:
			_start_boost_sound()

func _on_disable() -> void:
	if enable_audio:
		_stop_all_thruster_sounds()

func physics_process_component(delta: float) -> void:
	if not _rigid_body or not enabled:
		return
	
	# Only recalculate direction vectors when rotation changes
	if _rigid_body.rotation != _last_rotation:
		_update_direction_vectors()
		_last_rotation = _rigid_body.rotation
	
	# Fast path: Get modified movement values
	var current_thrust = thrust_force
	var current_reverse = reverse_force
	var current_rotation = rotation_force
	var current_max_speed = max_speed
	
	# Apply strategies - only if we have strategies
	if not _movement_strategies.is_empty():
		for strategy in _movement_strategies:
			if strategy.has_method("modify_thrust"):
				current_thrust = strategy.modify_thrust(current_thrust)
			if strategy.has_method("modify_reverse_thrust"):
				current_reverse = strategy.modify_reverse_thrust(current_reverse)
			if strategy.has_method("modify_rotation"):
				current_rotation = strategy.modify_rotation(current_rotation)
			if strategy.has_method("modify_max_speed"):
				current_max_speed = strategy.modify_max_speed(current_max_speed)
	
	# Apply boost multiplier
	if _is_boosting:
		current_thrust *= boost_multiplier
		current_reverse *= boost_multiplier
		
		# Handle boost consumption
		_current_boost_fuel -= boost_fuel_consumption * delta
		if _current_boost_fuel <= 0:
			_current_boost_fuel = 0
			stop_boost()
			boost_depleted.emit()
	elif boost_enabled and _current_boost_fuel < boost_fuel:
		# Regenerate boost fuel
		_current_boost_fuel = min(_current_boost_fuel + (boost_fuel_regen * delta), boost_fuel)
		
		# Signal full recharge
		if _current_boost_fuel >= boost_fuel and _boost_cooldown_remaining <= 0:
			boost_recharged.emit()
	
	# Update boost cooldown
	if _boost_cooldown_remaining > 0:
		_boost_cooldown_remaining -= delta
	
	# Handle movement based on input state - bitflag checks are faster
	if _input_state & INPUT_FORWARD:
		_rigid_body.apply_central_force(_cached_direction_right * current_thrust)
		_set_thruster_emission(_main_thruster, true)
	else:
		_set_thruster_emission(_main_thruster, false)
	
	# Handle backward movement
	if _input_state & INPUT_BACKWARD:
		_rigid_body.apply_central_force(_cached_direction_left * current_reverse)
		
		if enable_audio and not _backward_thruster_active:
			_start_backward_thruster_sound()
		
		# Turning while moving backward - combined bitwise checks
		if _input_state & INPUT_RIGHT:
			_set_thruster_emission(_right_thruster_front, true)
			_set_thruster_emission(_left_thruster_front, false)
			_rigid_body.apply_torque(current_rotation * 0.3)
		elif _input_state & INPUT_LEFT:
			_set_thruster_emission(_left_thruster_front, true)
			_set_thruster_emission(_right_thruster_front, false)
			_rigid_body.apply_torque(-current_rotation * 0.3)
		else:
			_set_thruster_emission(_left_thruster_front, true)
			_set_thruster_emission(_right_thruster_front, true)
	else:
		_set_thruster_emission(_left_thruster_front, false)
		_set_thruster_emission(_right_thruster_front, false)
		
		if _backward_thruster_active:
			_stop_backward_thruster_sound()
	
	# Handle rotation while not moving backward
	if not (_input_state & INPUT_BACKWARD):
		if _input_state & INPUT_RIGHT:
			_set_thruster_emission(_left_thruster_rear, true)
			_rigid_body.apply_torque(current_rotation)
		else:
			_set_thruster_emission(_left_thruster_rear, false)
		
		if _input_state & INPUT_LEFT:
			_set_thruster_emission(_right_thruster_rear, true)
			_rigid_body.apply_torque(-current_rotation)
		else:
			_set_thruster_emission(_right_thruster_rear, false)
	
	# Cap maximum speed - only calculate length once
	var speed = _rigid_body.linear_velocity.length()
	if speed > current_max_speed:
		_rigid_body.linear_velocity = _rigid_body.linear_velocity.normalized() * current_max_speed
	
	# Apply dampening
	_rigid_body.linear_velocity *= dampening_factor
	
	# Update audio positions if needed
	if enable_audio:
		_update_audio_positions()

# Optimized direction vector updates - only called when needed
func _update_direction_vectors() -> void:
	var sin_rot = sin(_rigid_body.rotation)
	var cos_rot = cos(_rigid_body.rotation)
	_cached_direction_right = Vector2(cos_rot, sin_rot)
	_cached_direction_left = Vector2(-cos_rot, -sin_rot)

# Consolidated input handling with bitflags
func thrust_forward(activate: bool = true) -> void:
	var was_thrusting = _input_state & INPUT_FORWARD
	
	if activate:
		_input_state |= INPUT_FORWARD
	else:
		_input_state &= ~INPUT_FORWARD
		
	if was_thrusting != (_input_state & INPUT_FORWARD):
		if enable_audio:
			if _input_state & INPUT_FORWARD:
				_start_main_thruster_sound()
			else:
				_stop_main_thruster_sound()
		thrusting_changed.emit((_input_state & INPUT_FORWARD) != 0)

func thrust_backward(activate: bool = true) -> void:
	if activate:
		_input_state |= INPUT_BACKWARD
	else:
		_input_state &= ~INPUT_BACKWARD

func rotate_left() -> void:
	_input_state |= INPUT_LEFT
	_input_state &= ~INPUT_RIGHT
	
	if enable_audio and not _rotation_thruster_active:
		_start_rotation_thruster_sound()

func rotate_right() -> void:
	_input_state |= INPUT_RIGHT
	_input_state &= ~INPUT_LEFT
	
	if enable_audio and not _rotation_thruster_active:
		_start_rotation_thruster_sound()

func stop_rotation() -> void:
	var was_rotating = _input_state & (INPUT_LEFT | INPUT_RIGHT)
	_input_state &= ~(INPUT_LEFT | INPUT_RIGHT)
	
	if was_rotating and enable_audio:
		_stop_rotation_thruster_sound()

func start_boost() -> void:
	if not boost_enabled or _is_boosting or _boost_cooldown_remaining > 0 or _current_boost_fuel <= 0:
		return
	
	_is_boosting = true
	
	if enable_audio:
		_start_boost_sound()
		
	boost_activated.emit()

func stop_boost() -> void:
	if not _is_boosting:
		return
	
	_is_boosting = false
	_boost_cooldown_remaining = boost_cooldown
	
	if enable_audio:
		_stop_boost_sound()

# Optimized audio handling with fewer checks
func _start_main_thruster_sound() -> void:
	if _main_thruster_active or _audio_manager == null:
		return
	
	_main_thruster_active = true
	_main_thruster_player = _audio_manager.play_sfx(
		main_thruster_sound_name, 
		owner_entity.global_position, 
		1.0, 
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
		main_thruster_sound_name, 
		owner_entity.global_position, 
		1.1,
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
		main_thruster_sound_name, 
		owner_entity.global_position, 
		0.9,
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

# Optimized thruster effects
func _set_thruster_emission(thruster: Node, emitting: bool) -> void:
	if thruster == null:
		return
		
	if thruster is CPUParticles2D or thruster is GPUParticles2D:
		thruster.emitting = emitting
	elif thruster is Node2D:
		thruster.visible = emitting

# Optimized position updates only for active sounds
func _update_audio_positions() -> void:
	var pos = owner_entity.global_position
	
	if _main_thruster_active and _main_thruster_player:
		_main_thruster_player.global_position = pos
	if _rotation_thruster_active and _rotation_thruster_player:
		_rotation_thruster_player.global_position = pos
	if _backward_thruster_active and _backward_thruster_player:
		_backward_thruster_player.global_position = pos
	if _boost_sound_active and _boost_thruster_player:
		_boost_thruster_player.global_position = pos

# Public API methods
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
