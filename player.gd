extends Node2D

@export var movement_speed = 300
@export var player_size = Vector2(32, 32)
@export var player_color = Color(1.0, 0.5, 0.0, 1.0)  # Orange

# Track if player is immobilized
var immobilized = false

# Add a camera if one doesn't exist
func _ready():
	# Set a high z-index to ensure the player is drawn on top of all other objects
	z_index = 10
	
	# Add a camera if one doesn't exist
	if not has_node("Camera2D"):
		var camera = Camera2D.new()
		camera.name = "Camera2D"
		camera.current = true
		add_child(camera)
		print("Added camera to player")
	
	print("Player ready at position: ", global_position)

func _process(delta):
	# Skip movement if player is immobilized
	if immobilized:
		return
		
	# Handle movement
	var direction = Vector2.ZERO
	
	if Input.is_action_pressed("ui_right"):
		direction.x += 1
	if Input.is_action_pressed("ui_left"):
		direction.x -= 1
	if Input.is_action_pressed("ui_down"):
		direction.y += 1
	if Input.is_action_pressed("ui_up"):
		direction.y -= 1
	
	if direction.length() > 0:
		direction = direction.normalized()
		global_position += direction * movement_speed * delta
	
	# Keep the player visible at all times by forcing a redraw
	queue_redraw()

func _draw():
	# Draw the player as an orange square
	var rect = Rect2(-player_size.x/2, -player_size.y/2, player_size.x, player_size.y)
	draw_rect(rect, player_color)
	
	# Add a border
	draw_rect(rect, Color.WHITE, false, 2.0)

# Method to completely immobilize the player
func set_immobilized(value):
	immobilized = value
	if value:
		print("Player immobilized")
	else:
		print("Player movement restored")
