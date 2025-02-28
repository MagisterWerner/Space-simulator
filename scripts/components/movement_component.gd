extends Component
class_name MovementComponent

signal facing_direction_changed(direction)
signal position_changed(old_position, new_position)
signal cell_changed(new_cell_x, new_cell_y)

@export var speed: float = 300.0
@export var rotate_sprite: bool = true

var velocity: Vector2 = Vector2.ZERO
var facing_direction: Vector2 = Vector2.RIGHT
var sprite: Sprite2D = null
var last_position: Vector2 = Vector2.ZERO
var cell_x: int = -1
var cell_y: int = -1
var grid = null

func _initialize():
	sprite = entity.get_node_or_null("Sprite2D")
	last_position = entity.global_position
	
	# Try to find the grid
	grid = entity.get_node_or_null("/root/Main/Grid")
	
	# Calculate initial cell position
	update_cell_position()

func _physics_process(delta):
	if velocity.length() > 0:
		# Move the entity
		var old_position = entity.global_position
		entity.global_position += velocity * delta
		
		# Update facing direction if velocity changed it
		if velocity.normalized() != facing_direction:
			facing_direction = velocity.normalized()
			emit_signal("facing_direction_changed", facing_direction)
			
			# Rotate sprite if enabled
			if rotate_sprite and sprite:
				sprite.rotation = facing_direction.angle()
		
		# Emit position changed signal
		if entity.global_position != old_position:
			emit_signal("position_changed", old_position, entity.global_position)
			
			# Check if cell position changed
			update_cell_position()

func move(direction: Vector2):
	velocity = direction.normalized() * speed

func stop():
	velocity = Vector2.ZERO

func set_speed(new_speed: float):
	speed = new_speed

func set_facing_direction(direction: Vector2):
	if direction.length() > 0:
		facing_direction = direction.normalized()
		emit_signal("facing_direction_changed", facing_direction)
		
		if rotate_sprite and sprite:
			sprite.rotation = facing_direction.angle()

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
