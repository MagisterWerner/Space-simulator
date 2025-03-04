# boundary.gd
extends Area2D

@export var boundary_size: Vector2 = Vector2(10000, 10000)
@export var wrap_mode: bool = true

func _ready() -> void:
	var collision_shape = $CollisionShape2D
	var shape = RectangleShape2D.new()
	shape.size = boundary_size
	collision_shape.shape = shape

func _on_body_exited(body: Node2D) -> void:
	if not wrap_mode or not body.is_in_group("player"):
		return
	
	var new_position = body.position
	
	# Calculate half sizes for wrapping
	var half_width = boundary_size.x / 2
	var half_height = boundary_size.y / 2
	
	# Wrap horizontally
	if body.position.x > half_width:
		new_position.x = -half_width
	elif body.position.x < -half_width:
		new_position.x = half_width
	
	# Wrap vertically
	if body.position.y > half_height:
		new_position.y = -half_height
	elif body.position.y < -half_height:
		new_position.y = half_height
	
	# Apply new position
	body.position = new_position
