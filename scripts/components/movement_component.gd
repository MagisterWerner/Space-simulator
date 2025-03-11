# scripts/components/movement_component.gd
# Movement component that handles ship thrust, rotation, and boost functionality
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

# These paths should be relative to the owner (PlayerShip)
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

var _is_thrusting_forward: bool = false
var _is_thrusting_backward: bool = false
var _rotation_direction: float = 0.0
var _is_boosting: bool = false
var _boost_cooldown_remaining: float = 0.0
var _current_boost_fuel: float = 100.0
var _rigid_body: RigidBody2D
var _movement_strategies: Array = []

# Thruster node references
var _main_thruster: Node
var _left_thruster_rear: Node
var _left_thruster_front: Node
var _right_thruster_rear: Node
var _right_thruster_front: Node
var _left_position: Node2D
var _right_position: Node2D

# Audio state tracking
var _main_thruster_player = null
var _rotation_thruster_player = null
var _backward_thruster_player = null
var _boost_thruster_player = null
var _main_thruster_active: bool = false
var _rotation_thruster_active: bool = false
var _backward_thruster_active: bool = false
var _boost_sound_active: bool = false
var _audio_manager = null

# Static flag for tracking console messages across all movement components
static var _has_logged_init: bool = false

func setup() -> void:
	if owner_entity is RigidBody2D:
		_rigid_body = owner_entity
		
		# Using a static flag to ensure the message only prints once
		if not _has_logged_init:
			print("MovementComponent: Successfully attached to RigidBody2D")
			_has_logged_init = true
	else:
		push_error("MovementComponent: Owner is not a RigidBody2D")
		disable()
		return
	
	_current_boost_fuel = boost_fuel
	
	# Find thruster nodes - try both with and without paths
	_find_thruster_nodes()
	
	# Get a direct reference to AudioManager at setup time
	_audio_manager = _get_audio_manager()
	
	# Initialize audio with a slight delay to ensure AudioManager is ready
	call_deferred("_initialize_audio")
	
	debug_print("Movement component setup complete")

func _get_audio_manager():
	# Try multiple approaches to get the AudioManager
	var audio_mgr = null
	
	# First try getting it as an autoload from the root
	if Engine.get_main_loop() and Engine.get_main_loop().root.has_node("AudioManager"):
		audio_mgr = Engine.get_main_loop().root.get_node("AudioManager")
		debug_print("Found AudioManager via root node")
		return audio_mgr
	
	# Try the simpler approach if the previous didn't work
	audio_mgr = get_node_or_null("/root/AudioManager")
	if audio_mgr:
		debug_print("Found AudioManager via direct path")
		return audio_mgr
	
	# Manually load the script if all else fails
	var script = load("res://autoload/audio_manager.gd")
	if script:
		audio_mgr = script.new()
		debug_print("Created AudioManager instance manually")
		return audio_mgr
	
	push_warning("MovementComponent: AudioManager not found")
	return null

func _initialize_audio() -> void:
	if not enable_audio:
		return
	
	if _audio_manager == null:
		_audio_manager = _get_audio_manager()
		if _audio_manager == null:
			push_warning("MovementComponent: AudioManager still not available after deferred initialization")
			return
	
	debug_print("Initializing audio with manager: " + str(_audio_manager))
	
	# Preload the thruster sounds if not already loaded
	if _audio_manager.has_method("is_sfx_loaded"):
		# Main thruster sound
		if not _audio_manager.is_sfx_loaded(main_thruster_sound_name):
			var sound_path = "res://assets/audio/thruster.wav"
			if ResourceLoader.exists(sound_path):
				_audio_manager.preload_sfx(main_thruster_sound_name, sound_path, 2)
				debug_print("Preloaded main thruster sound from: " + sound_path)
			else:
				push_warning("MovementComponent: Thruster sound file not found: " + sound_path)
		
		# Rotation thruster sound (if different from main)
		if rotation_thruster_sound_name != main_thruster_sound_name and not _audio_manager.is_sfx_loaded(rotation_thruster_sound_name):
			var sound_path = "res://assets/audio/thruster.wav"
			if ResourceLoader.exists(sound_path):
				_audio_manager.preload_sfx(rotation_thruster_sound_name, sound_path, 2)
				debug_print("Preloaded rotation thruster sound")
		
		# Backward thruster sound (if different from others)
		if backward_thruster_sound_name != main_thruster_sound_name and backward_thruster_sound_name != rotation_thruster_sound_name and not _audio_manager.is_sfx_loaded(backward_thruster_sound_name):
			var sound_path = "res://assets/audio/thruster.wav"
			if ResourceLoader.exists(sound_path):
				_audio_manager.preload_sfx(backward_thruster_sound_name, sound_path, 2)
				debug_print("Preloaded backward thruster sound")
		
		# Boost sound (if different from thrusters)
		if boost_sound_name != main_thruster_sound_name and boost_sound_name != rotation_thruster_sound_name and boost_sound_name != backward_thruster_sound_name and not _audio_manager.is_sfx_loaded(boost_sound_name):
			var boost_path = "res://assets/audio/thruster.wav"  # Default to thruster if boost not found
			if ResourceLoader.exists("res://assets/audio/boost.wav"):
				boost_path = "res://assets/audio/boost.wav"
			_audio_manager.preload_sfx(boost_sound_name, boost_path, 1)
			debug_print("Preloaded boost sound")

func _on_enable() -> void:
	# Start any active audio again if it was playing before
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
	_stop_all_thruster_sounds()

func _find_thruster_nodes() -> void:
	# First try using the exported paths
	if !main_thruster_path.is_empty():
		_main_thruster = owner_entity.get_node_or_null(main_thruster_path)
	
	if !left_thruster_rear_path.is_empty():
		_left_thruster_rear = owner_entity.get_node_or_null(left_thruster_rear_path)
	
	if !left_thruster_front_path.is_empty():
		_left_thruster_front = owner_entity.get_node_or_null(left_thruster_front_path)
	
	if !right_thruster_rear_path.is_empty():
		_right_thruster_rear = owner_entity.get_node_or_null(right_thruster_rear_path)
	
	if !right_thruster_front_path.is_empty():
		_right_thruster_front = owner_entity.get_node_or_null(right_thruster_front_path)
	
	if !left_position_path.is_empty():
		_left_position = owner_entity.get_node_or_null(left_position_path)
	
	if !right_position_path.is_empty():
		_right_position = owner_entity.get_node_or_null(right_position_path)
	
	# If paths didn't work, try searching by common names
	if _main_thruster == null:
		_main_thruster = owner_entity.find_child("MainThruster", true, false)
		debug_print("Found main thruster by search: " + str(_main_thruster != null))
	
	# Try to find left/right positions if not found already
	if _left_position == null:
		_left_position = owner_entity.find_child("L", true, false)
		if _left_position == null:
			_left_position = owner_entity.find_child("Left", true, false)
		debug_print("Found left position by search: " + str(_left_position != null))
	
	if _right_position == null:
		_right_position = owner_entity.find_child("R", true, false)
		if _right_position == null:
			_right_position = owner_entity.find_child("Right", true, false)
		debug_print("Found right position by search: " + str(_right_position != null))
	
	# Try to find thruster particles if not found already
	if _left_thruster_rear == null and _left_position != null:
		_left_thruster_rear = _left_position.find_child("RearThruster", true, false)
	
	if _left_thruster_front == null and _left_position != null:
		_left_thruster_front = _left_position.find_child("FrontThruster", true, false)
	
	if _right_thruster_rear == null and _right_position != null:
		_right_thruster_rear = _right_position.find_child("RearThruster", true, false)
	
	if _right_thruster_front == null and _right_position != null:
		_right_thruster_front = _right_position.find_child("FrontThruster", true, false)
	
	# Log what we found
	debug_print("Thrusters found: Main=" + str(_main_thruster != null) + 
				", LR=" + str(_left_thruster_rear != null) + 
				", LF=" + str(_left_thruster_front != null) + 
				", RR=" + str(_right_thruster_rear != null) + 
				", RF=" + str(_right_thruster_front != null))

func physics_process_component(delta: float) -> void:
	if not _rigid_body or not enabled:
		return
	
	# Apply strategies to movement properties
	var modified_thrust = thrust_force
	var modified_reverse = reverse_force
	var modified_rotation = rotation_force
	var modified_max_speed = max_speed
	
	for strategy in _movement_strategies:
		if strategy.has_method("modify_thrust"):
			modified_thrust = strategy.modify_thrust(modified_thrust)
		if strategy.has_method("modify_reverse_thrust"):
			modified_reverse = strategy.modify_reverse_thrust(modified_reverse)
		if strategy.has_method("modify_rotation"):
			modified_rotation = strategy.modify_rotation(modified_rotation)
		if strategy.has_method("modify_max_speed"):
			modified_max_speed = strategy.modify_max_speed(modified_max_speed)
	
	# Apply boost if active
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
		if _current_boost_fuel == boost_fuel and _boost_cooldown_remaining <= 0:
			boost_recharged.emit()
	
	# Update boost cooldown
	if _boost_cooldown_remaining > 0:
		_boost_cooldown_remaining -= delta
	
	# IMPORTANT: The ship sprite is oriented pointing right (0 degrees)
	# So for correct "forward" motion, we need to match this orientation
	
	# Handle forward thrust (right direction since ship points right)
	if _is_thrusting_forward:
		# Apply force in the direction the ship is facing
		var forward_direction = Vector2.RIGHT.rotated(_rigid_body.rotation) * modified_thrust
		_rigid_body.apply_central_force(forward_direction)
		_set_thruster_emission(_main_thruster, true)
	else:
		_set_thruster_emission(_main_thruster, false)
	
	# Handle backward movement (left direction since ship points right)
	if _is_thrusting_backward:
		# Apply force opposite to the direction the ship is facing
		var backward_direction = Vector2.LEFT.rotated(_rigid_body.rotation) * modified_reverse
		_rigid_body.apply_central_force(backward_direction)
		
		# Start backward thruster sound if not already playing
		if enable_audio and not _backward_thruster_active:
			_start_backward_thruster_sound()
		
		# When moving backward, use front thrusters for turning
		if _rotation_direction > 0 and _right_position != null:  # Turn right while moving backward
			_set_thruster_emission(_right_thruster_front, true)
			_set_thruster_emission(_left_thruster_front, false)
			
			if _right_position:
				var torque_force = modified_rotation * 0.3 # Reduced for better control
				_rigid_body.apply_torque(torque_force)
			
		elif _rotation_direction < 0 and _left_position != null:  # Turn left while moving backward
			_set_thruster_emission(_left_thruster_front, true)
			_set_thruster_emission(_right_thruster_front, false)
			
			if _left_position:
				var torque_force = -modified_rotation * 0.3 # Reduced for better control
				_rigid_body.apply_torque(torque_force)
			
		else:  # Just moving backward without turning
			_set_thruster_emission(_left_thruster_front, true)
			_set_thruster_emission(_right_thruster_front, true)
	else:
		_set_thruster_emission(_left_thruster_front, false)
		_set_thruster_emission(_right_thruster_front, false)
		
		# Stop backward thruster sound if it was playing
		if _backward_thruster_active:
			_stop_backward_thruster_sound()
	
	# Handle rotation while not moving backward
	if not _is_thrusting_backward:
		if _rotation_direction > 0:  # Turn right (using left thruster)
			_set_thruster_emission(_left_thruster_rear, true)
			_rigid_body.apply_torque(modified_rotation)
		else:
			_set_thruster_emission(_left_thruster_rear, false)
		
		if _rotation_direction < 0:  # Turn left (using right thruster)
			_set_thruster_emission(_right_thruster_rear, true)
			_rigid_body.apply_torque(-modified_rotation)
		else:
			_set_thruster_emission(_right_thruster_rear, false)
	
	# Cap maximum speed
	if _rigid_body.linear_velocity.length() > modified_max_speed:
		_rigid_body.linear_velocity = _rigid_body.linear_velocity.normalized() * modified_max_speed
	
	# Apply speed dampening
	_rigid_body.linear_velocity *= dampening_factor
	
	# Update audio positions
	_update_audio_positions()

func _update_audio_positions() -> void:
	if not owner_entity or not enable_audio:
		return
		
	# Update position for active sound players
	if _main_thruster_active and _main_thruster_player:
		_main_thruster_player.position = owner_entity.global_position
	
	if _rotation_thruster_active and _rotation_thruster_player:
		_rotation_thruster_player.position = owner_entity.global_position
		
	if _backward_thruster_active and _backward_thruster_player:
		_backward_thruster_player.position = owner_entity.global_position
		
	if _boost_sound_active and _boost_thruster_player:
		_boost_thruster_player.position = owner_entity.global_position

func thrust_forward(activate: bool = true) -> void:
	var was_active = _is_thrusting_forward
	_is_thrusting_forward = activate
	
	if enable_audio and was_active != _is_thrusting_forward:
		if _is_thrusting_forward:
			_start_main_thruster_sound()
		else:
			_stop_main_thruster_sound()
	
	if _is_thrusting_forward != was_active:
		thrusting_changed.emit(_is_thrusting_forward)

func thrust_backward(activate: bool = true) -> void:
	_is_thrusting_backward = activate
	
	# Audio is now handled in the physics_process_component for backward movement

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
	debug_print("Boost activated")

func stop_boost() -> void:
	if not _is_boosting:
		return
	
	_is_boosting = false
	_boost_cooldown_remaining = boost_cooldown
	
	if enable_audio:
		_stop_boost_sound()
		
	debug_print("Boost stopped")

# Audio control methods
func _start_main_thruster_sound() -> void:
	if not enable_audio or _main_thruster_active or _audio_manager == null:
		return
	
	_main_thruster_active = true
	
	if _audio_manager.has_method("play_sfx"):
		_main_thruster_player = _audio_manager.play_sfx(
			main_thruster_sound_name, 
			owner_entity.global_position, 
			main_thruster_pitch, 
			main_thruster_volume_db
		)
		
		# Configure for looping
		if _main_thruster_player and _main_thruster_player.stream and not _main_thruster_player.stream.loop_mode:
			var stream = _main_thruster_player.stream as AudioStreamWAV
			if stream:
				stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
				stream.loop_begin = 0
				stream.loop_end = stream.data.size()
	else:
		debug_print("AudioManager found but play_sfx method not available")

func _stop_main_thruster_sound() -> void:
	if not _main_thruster_active:
		return
	
	_main_thruster_active = false
	
	if _main_thruster_player:
		_main_thruster_player.stop()
		_main_thruster_player = null

func _start_rotation_thruster_sound() -> void:
	if not enable_audio or _rotation_thruster_active or _audio_manager == null:
		return
	
	_rotation_thruster_active = true
	
	if _audio_manager.has_method("play_sfx"):
		_rotation_thruster_player = _audio_manager.play_sfx(
			rotation_thruster_sound_name, 
			owner_entity.global_position, 
			rotation_thruster_pitch,
			rotation_thruster_volume_db
		)
		
		# Configure for looping
		if _rotation_thruster_player and _rotation_thruster_player.stream and not _rotation_thruster_player.stream.loop_mode:
			var stream = _rotation_thruster_player.stream as AudioStreamWAV
			if stream:
				stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
				stream.loop_begin = 0
				stream.loop_end = stream.data.size()

func _stop_rotation_thruster_sound() -> void:
	if not _rotation_thruster_active:
		return
	
	_rotation_thruster_active = false
	
	if _rotation_thruster_player:
		_rotation_thruster_player.stop()
		_rotation_thruster_player = null

func _start_backward_thruster_sound() -> void:
	if not enable_audio or _backward_thruster_active or _audio_manager == null:
		return
	
	_backward_thruster_active = true
	
	if _audio_manager.has_method("play_sfx"):
		_backward_thruster_player = _audio_manager.play_sfx(
			backward_thruster_sound_name, 
			owner_entity.global_position, 
			backward_thruster_pitch,
			backward_thruster_volume_db
		)
		
		# Configure for looping
		if _backward_thruster_player and _backward_thruster_player.stream and not _backward_thruster_player.stream.loop_mode:
			var stream = _backward_thruster_player.stream as AudioStreamWAV
			if stream:
				stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
				stream.loop_begin = 0
				stream.loop_end = stream.data.size()
	else:
		debug_print("AudioManager found but play_sfx method not available for backward thruster")

func _stop_backward_thruster_sound() -> void:
	if not _backward_thruster_active:
		return
	
	_backward_thruster_active = false
	
	if _backward_thruster_player:
		_backward_thruster_player.stop()
		_backward_thruster_player = null

func _start_boost_sound() -> void:
	if not enable_audio or _boost_sound_active or _audio_manager == null:
		return
	
	_boost_sound_active = true
	
	if _audio_manager.has_method("play_sfx"):
		_boost_thruster_player = _audio_manager.play_sfx(
			boost_sound_name, 
			owner_entity.global_position, 
			0.9, # Slightly lower pitch for boost
			0.0  # Full volume
		)
	else:
		debug_print("AudioManager found but play_sfx method not available for boost sound")

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

# Helpers
func get_boost_fuel_percent() -> float:
	return _current_boost_fuel / boost_fuel

func get_current_velocity() -> Vector2:
	if _rigid_body:
		return _rigid_body.linear_velocity
	return Vector2.ZERO

func get_current_speed() -> float:
	return get_current_velocity().length()

func _set_thruster_emission(thruster: Node, emitting: bool) -> void:
	if thruster == null:
		return
		
	if thruster is CPUParticles2D:
		thruster.emitting = emitting
	elif thruster is GPUParticles2D:
		thruster.emitting = emitting
	elif thruster.has_method("set_deferred"):
		thruster.set_deferred("emitting", emitting)
	elif thruster is Node2D:
		thruster.visible = emitting

func add_movement_strategy(strategy) -> void:
	if not _movement_strategies.has(strategy):
		_movement_strategies.append(strategy)
		
func remove_movement_strategy(strategy) -> void:
	_movement_strategies.erase(strategy)
