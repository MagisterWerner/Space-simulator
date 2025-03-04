# physics_movement_component.gd
extends Component
class_name PhysicsMovementComponent

signal facing_direction_changed(direction)
signal position_changed(old_position, new_position)
signal cell_changed(new_cell_x, new_cell_y)

@export var thrust_force: float = 500.0
@export var rotation_speed: float = 5.0
@export var max_speed: float = 300.0
@export var damp_factor: float = 0.1

var velocity: Vector2 = Vector2.ZERO
var facing_direction: Vector2 = Vector2.RIGHT
var target_direction: Vector2 = Vector2.ZERO
var sprite: Sprite2D
var last_position: Vector2 = Vector2.ZERO
var cell_x: int = -1
var cell_y: int = -1
var grid = null
var rigid_body: RigidBody2D

func _initialize():
	sprite = entity.get_node_or_null("Sprite2D")
	last_position = entity.global_position
	
	rigid_body = entity as RigidBody2D
	if not rigid_body:
		push_error("PhysicsMovementComponent requires a RigidBody2D parent!")
		return
		
	rigid_body.gravity_scale = 0.0
	rigid_body.linear_damp = damp_factor
	rigid_body.angular_damp = damp_factor * 10
	rigid_body.can_sleep = false
	
	grid = entity.get_node_or_null("/root/Main/Grid")
	update_cell_position()

func _physics_process(delta):
	if not rigid_body:
		return
	
	last_position = entity.global_position
	
	if target_direction.length() > 0.1:
		var target_angle = target_direction.angle()
		var current_angle = rigid_body.rotation
		var angle_diff = wrapf(target_angle - current_angle, -PI, PI)
		
		rigid_body.applied_torque = angle_diff * rotation_speed * 100
		facing_direction = Vector2(cos(rigid_body.rotation), sin(rigid_body.rotation))
		
		rigid_body.apply_central_force(facing_direction * thrust_force * target_direction.length())
	
	if entity.global_position != last_position:
		emit_signal("position_changed", last_position, entity.global_position)
		update_cell_position()
	
	velocity = rigid_body.linear_velocity
	
	if velocity.length() > max_speed:
		rigid_body.linear_velocity = velocity.normalized() * max_speed

func move(direction: Vector2):
	target_direction = direction.normalized() if direction.length() > 0 else Vector2.ZERO

func stop():
	target_direction = Vector2.ZERO
	
	if rigid_body and rigid_body.linear_velocity.length() > 0:
		rigid_body.apply_central_force(-rigid_body.linear_velocity.normalized() * thrust_force * 0.5)

func set_speed(new_speed: float):
	max_speed = new_speed

func set_facing_direction(direction: Vector2):
	if direction.length() > 0:
		target_direction = direction.normalized()
		emit_signal("facing_direction_changed", direction.normalized())

func update_cell_position() -> bool:
	if not grid:
		return false
		
	var new_cell_x = int(entity.global_position.x / grid.cell_size.x)
	var new_cell_y = int(entity.global_position.y / grid.cell_size.y)
	
	if new_cell_x != cell_x or new_cell_y != cell_y:
		cell_x = new_cell_x
		cell_y = new_cell_y
		emit_signal("cell_changed", cell_x, cell_y)
		
		if grid.has_method("update_loaded_chunks"):
			grid.update_loaded_chunks(cell_x, cell_y)
			
		return true
	
	return false

func get_current_cell() -> Vector2i:
	return Vector2i(cell_x, cell_y)
