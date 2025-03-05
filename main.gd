# main.gd
extends Node2D

@onready var player_ship = $PlayerShip
@onready var camera = $Camera2D

var screen_size: Vector2

func _ready() -> void:
	screen_size = get_viewport_rect().size
	
	# Position the player ship
	player_ship.position = screen_size / 2
	camera.position = player_ship.position
	
	# Allow one frame for autoloads to complete initialization
	await get_tree().process_frame
	
	# Start the game using the autoloaded GameManager
	Game.start_game()

func _process(_delta: float) -> void:
	# Follow player from GameManager if available, otherwise use local reference
	if Game.player_ship and is_instance_valid(Game.player_ship):
		camera.position = Game.player_ship.position
	else:
		camera.position = player_ship.position
