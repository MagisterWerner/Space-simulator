# scripts/components/physics_movement_component.gd
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
var sprite: Sprite2D = null
var last_position: Vector2 = Vector2.ZERO
var cell_x: int = -1
var cell_y: int = -1
var grid = null
var rigid_body: RigidBody2D = null

func _initialize():
	sprite = entity.get_node_or_null("Sprite2D")
	last_position = entity.global_position
	
	# Get the RigidBody2D reference
	rigid_body = entity as RigidBody2D
	if rigid_body:
		# Set up physics properties
		rigid_body.gravity_scale = 0.0  # No gravity in space
		rigid_body.linear_damp = damp_factor
		rigid_body.angular_damp = damp_factor * 10  # Higher angular damping to prevent wild rotation
		rigid_body.can_sleep = false  # Don't let the physics engine put the body to sleep
	else:
		push_error("PhysicsMovementComponent requires a RigidBody2D parent!")
	
	# Try to find the grid
	grid = entity.get_node_or_null("/root/Main/Grid")
	
	# Calculate initial cell position
	update_cell_position()

func _physics_process(delta):
	if not rigid_body:
		return
	
	# Store the last position for comparison
	last_position = entity.global_position
	
	# Apply rotation towards target direction
	if target_direction.length() > 0.1:
		var target_angle = target_direction.angle()
		var current_angle = rigid_body.rotation
		
		# Find the shortest path to rotate
		var angle_diff = wrapf(target_angle - current_angle, -PI, PI)
		
		# Apply torque for rotation
		rigid_body.applied_torque = angle_diff * rotation_speed * 100
		
		# Update facing direction based on actual rotation
		facing_direction = Vector2(cos(rigid_body.rotation), sin(rigid_body.rotation))
		
		# Apply thrust force in the facing direction
		var thrust = facing_direction * thrust_force * target_direction.length()
		rigid_body.apply_central_force(thrust)
	
	# Emit position changed signal if position changed
	if entity.global_position != last_position:
		emit_signal("position_changed", last_position, entity.global_position)
		
		# Check if cell position changed
		update_cell_position()
	
	# Update velocity for compatibility
	velocity = rigid_body.linear_velocity
	
	# Cap speed if exceeding maximum
	if velocity.length() > max_speed:
		rigid_body.linear_velocity = velocity.normalized() * max_speed

func move(direction: Vector2):
	if direction.length() > 0:
		target_direction = direction.normalized()
	else:
		target_direction = Vector2.ZERO

func stop():
	target_direction = Vector2.ZERO
	
	# Apply braking force when stopping
	if rigid_body and rigid_body.linear_velocity.length() > 0:
		rigid_body.apply_central_force(-rigid_body.linear_velocity.normalized() * thrust_force * 0.5)

func set_speed(new_speed: float):
	max_speed = new_speed

func set_facing_direction(direction: Vector2):
	if direction.length() > 0:
		target_direction = direction.normalized()
		emit_signal("facing_direction_changed", direction.normalized())

func update_cell_position() -> bool:
	if grid:
		var new_cell_x = int(entity.global_position.x / grid.cell_size.x)
		var new_cell_y = int(entity.global_position.y / grid.cell_size.y)
		
		if new_cell_x != cell_x or new_cell_y != cell_y:
			cell_x = new_cell_x
			cell_y = new_cell_y
			emit_signal("cell_changed", cell_x, cell_y)
			
			# Update loaded chunks in the grid if applicable
			if grid.has_method("update_loaded_chunks"):
				grid.update_loaded_chunks(cell_x, cell_y)
				
			return true
	
	return false

func get_current_cell() -> Vector2i:
	return Vector2i(cell_x, cell_y)
