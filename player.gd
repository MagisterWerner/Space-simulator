extends Node2D

@export var movement_speed = 300
@export var player_size = Vector2(32, 32)
@export var player_color = Color(1.0, 0.5, 0.0, 1.0)  # Orange

# Reference to the state machine
@onready var state_machine = $StateMachine

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

func _draw():
	# Draw the player as an orange square
	var rect = Rect2(-player_size.x/2, -player_size.y/2, player_size.x, player_size.y)
	draw_rect(rect, player_color)
	
	# Add a border
	draw_rect(rect, Color.WHITE, false, 2.0)

# Method to completely immobilize the player
func set_immobilized(value):
	if value:
		state_machine.change_state("Immobilized")
	else:
		state_machine.change_state("Normal")