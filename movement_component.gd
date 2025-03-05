# movement_component.gd
extends Component
class_name MovementComponent

signal thrusting_changed(is_thrusting)
signal boost_activated
signal boost_depleted
signal boost_recharged

@export_category("Movement Properties")
@export var thrust_force: float = 16.0  # Multiplier for forward impulse
@export var reverse_force: float = 4.0  # Multiplier for backward impulse
@export var rotation_force: float = 1.0  # Multiplier for rotation impulse
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

var _is_thrusting_forward: bool = false
var _is_thrusting_backward: bool = false
var _rotation_direction: float = 0.0
var _is_boosting: bool = false
# Removing unused variable: var _boost_time_remaining: float = 0.0
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

func setup() -> void:
	if owner_entity is RigidBody2D:
		_rigid_body = owner_entity
		print("MovementComponent: Successfully attached to RigidBody2D")
	else:
		push_error("MovementComponent: Owner is not a RigidBody2D")
		disable()
		return
	
	_current_boost_fuel = boost_fuel
	
	# Find thruster nodes - try both with and without paths
	_find_thruster_nodes()
	
	debug_print("Movement component setup complete")

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
	
	# Handle forward movement (based on original Player.gd)
	if _is_thrusting_forward:
		_rigid_body.apply_central_impulse(Vector2(0, -modified_thrust).rotated(_rigid_body.rotation))
		_set_thruster_emission(_main_thruster, true)
	else:
		_set_thruster_emission(_main_thruster, false)
	
	# Handle backward movement and rotation while moving backward
	if _is_thrusting_backward:
		_rigid_body.apply_central_impulse(Vector2(0, +modified_reverse).rotated(_rigid_body.rotation))
		
		# When moving backward, use front thrusters for turning
		if _rotation_direction > 0 and _right_position != null:  # Turn right while moving backward
			_set_thruster_emission(_right_thruster_front, true)
			_set_thruster_emission(_left_thruster_front, false)
			_rigid_body.apply_impulse(
				Vector2(0, +modified_rotation).rotated(_rigid_body.rotation),
				_right_position.position.rotated(_rigid_body.rotation)
			)
		elif _rotation_direction < 0 and _left_position != null:  # Turn left while moving backward
			_set_thruster_emission(_left_thruster_front, true)
			_set_thruster_emission(_right_thruster_front, false)
			_rigid_body.apply_impulse(
				Vector2(0, +modified_rotation).rotated(_rigid_body.rotation),
				_left_position.position.rotated(_rigid_body.rotation)
			)
		else:  # Just moving backward without turning
			_set_thruster_emission(_left_thruster_front, true)
			_set_thruster_emission(_right_thruster_front, true)
	else:
		_set_thruster_emission(_left_thruster_front, false)
		_set_thruster_emission(_right_thruster_front, false)
	
	# Handle rotation while not moving backward
	if not _is_thrusting_backward:
		if _rotation_direction > 0 and _left_position != null:  # Turn right (using left thruster)
			_set_thruster_emission(_left_thruster_rear, true)
			_rigid_body.apply_impulse(
				Vector2(0, -modified_rotation).rotated(_rigid_body.rotation),
				_left_position.position.rotated(_rigid_body.rotation)
			)
		else:
			_set_thruster_emission(_left_thruster_rear, false)
		
		if _rotation_direction < 0 and _right_position != null:  # Turn left (using right thruster)
			_set_thruster_emission(_right_thruster_rear, true)
			_rigid_body.apply_impulse(
				Vector2(0, -modified_rotation).rotated(_rigid_body.rotation),
				_right_position.position.rotated(_rigid_body.rotation)
			)
		else:
			_set_thruster_emission(_right_thruster_rear, false)
	
	# Cap maximum speed
	if _rigid_body.linear_velocity.length() > modified_max_speed:
		_rigid_body.linear_velocity = _rigid_body.linear_velocity.normalized() * modified_max_speed
	
	# Apply speed dampening
	_rigid_body.linear_velocity *= dampening_factor

func thrust_forward(activate: bool = true) -> void:
	if _is_thrusting_forward != activate:
		_is_thrusting_forward = activate
		thrusting_changed.emit(_is_thrusting_forward)

func thrust_backward(activate: bool = true) -> void:
	_is_thrusting_backward = activate

func rotate_left() -> void:
	_rotation_direction = -1.0

func rotate_right() -> void:
	_rotation_direction = 1.0

func stop_rotation() -> void:
	_rotation_direction = 0.0

func start_boost() -> void:
	if not boost_enabled or _is_boosting or _boost_cooldown_remaining > 0 or _current_boost_fuel <= 0:
		return
	
	_is_boosting = true
	boost_activated.emit()
	debug_print("Boost activated")

func stop_boost() -> void:
	if not _is_boosting:
		return
	
	_is_boosting = false
	_boost_cooldown_remaining = boost_cooldown
	debug_print("Boost stopped")

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
