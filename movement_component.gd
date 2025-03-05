# movement_component.gd
extends Component
class_name MovementComponent

signal thrusting_changed(is_thrusting)
signal boost_activated
signal boost_depleted
signal boost_recharged

@export_category("Movement Properties")
@export var thrust_force: float = 500.0
@export var rotation_speed: float = 2.5
@export var max_speed: float = 500.0
@export var dampening_factor: float = 0.99  # Applied when not thrusting

@export_category("Boost")
@export var boost_enabled: bool = true
@export var boost_multiplier: float = 2.0
@export var boost_duration: float = 3.0
@export var boost_cooldown: float = 5.0
@export var boost_fuel: float = 100.0
@export var boost_fuel_consumption: float = 30.0  # Per second
@export var boost_fuel_regen: float = 15.0  # Per second

@export_category("Thruster Effects")
@export var main_thruster_path: NodePath
@export var left_thruster_path: NodePath
@export var right_thruster_path: NodePath

var _is_thrusting: bool = false
var _rotation_direction: float = 0.0
var _is_boosting: bool = false
var _boost_time_remaining: float = 0.0
var _boost_cooldown_remaining: float = 0.0
var _current_boost_fuel: float = 100.0
var _rigid_body: RigidBody2D
var _movement_strategies: Array = []
var _main_thruster: Node2D
var _left_thruster: Node2D
var _right_thruster: Node2D

func setup() -> void:
	if owner_entity is RigidBody2D:
		_rigid_body = owner_entity
	else:
		push_error("MovementComponent: Owner is not a RigidBody2D")
		disable()
		return
	
	_current_boost_fuel = boost_fuel
	
	# Get thruster effects nodes
	if not main_thruster_path.is_empty():
		_main_thruster = get_node(main_thruster_path)
	
	if not left_thruster_path.is_empty():
		_left_thruster = get_node(left_thruster_path)
	
	if not right_thruster_path.is_empty():
		_right_thruster = get_node(right_thruster_path)
	
	_update_thruster_effects()

func physics_process_component(delta: float) -> void:
	if not _rigid_body:
		return
	
	# Apply strategies to movement properties
	var modified_thrust = thrust_force
	var modified_rotation = rotation_speed
	var modified_max_speed = max_speed
	
	for strategy in _movement_strategies:
		if strategy.has_method("modify_thrust"):
			modified_thrust = strategy.modify_thrust(modified_thrust)
		if strategy.has_method("modify_rotation"):
			modified_rotation = strategy.modify_rotation(modified_rotation)
		if strategy.has_method("modify_max_speed"):
			modified_max_speed = strategy.modify_max_speed(modified_max_speed)
	
	# Apply boost if active
	if _is_boosting:
		modified_thrust *= boost_multiplier
		
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
	
	# Apply rotation
	if _rotation_direction != 0:
		_rigid_body.apply_torque(_rotation_direction * modified_rotation * 250)
	
	# Apply thrust
	if _is_thrusting:
		var thrust_vector = Vector2(modified_thrust, 0).rotated(_rigid_body.rotation)
		_rigid_body.apply_central_force(thrust_vector)
	
	# Apply speed dampening
	if not _is_thrusting:
		_rigid_body.linear_velocity *= dampening_factor
	
	# Cap maximum speed
	if _rigid_body.linear_velocity.length() > modified_max_speed:
		_rigid_body.linear_velocity = _rigid_body.linear_velocity.normalized() * modified_max_speed
	
	_update_thruster_effects()

func thrust_forward(activate: bool = true) -> void:
	if _is_thrusting != activate:
		_is_thrusting = activate
		thrusting_changed.emit(_is_thrusting)

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

func _update_thruster_effects() -> void:
	# Main thruster visibility based on thrusting state
	if _main_thruster and _main_thruster.has_method("set_deferred"):
		_main_thruster.set_deferred("emitting", _is_thrusting)
	
	# Rotation thrusters
	if _left_thruster and _left_thruster.has_method("set_deferred"):
		_left_thruster.set_deferred("emitting", _rotation_direction > 0)
	
	if _right_thruster and _right_thruster.has_method("set_deferred"):
		_right_thruster.set_deferred("emitting", _rotation_direction < 0)

func add_movement_strategy(strategy) -> void:
	if not _movement_strategies.has(strategy):
		_movement_strategies.append(strategy)
		
func remove_movement_strategy(strategy) -> void:
	_movement_strategies.erase(strategy)
