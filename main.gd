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
	
	# Check if the Game autoload exists in the scene tree
	if has_node("/root/Game"):
		# Start the game using the autoloaded GameManager
		var game_manager = get_node("/root/Game")
		if game_manager.has_method("start_game"):
			game_manager.start_game()
		else:
			push_error("Game autoload found but doesn't have start_game method")
	else:
		push_error("Game autoload not found - check project settings")
		print("Available autoloads:")
		for child in get_node("/root").get_children():
			if child != get_tree().current_scene:
				print(" - " + child.name)

func _process(_delta: float) -> void:
	# Follow player from GameManager if available, otherwise use local reference
	if has_node("/root/Game"):
		var game_manager = get_node("/root/Game")
		if game_manager.player_ship and is_instance_valid(game_manager.player_ship):
			camera.position = game_manager.player_ship.position
		else:
			camera.position = player_ship.position
	else:
		camera.position = player_ship.position
