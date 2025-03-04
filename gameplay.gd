# gameplay.gd
extends Node2D

# Reference to the player ship
@onready var player_ship = $PlayerShip/Ship

func _ready():
	# Center player in the world on start
	player_ship.position = Vector2(640, 360)

# Called when entering the scene
func pre_start(params):
	var cur_scene = get_tree().current_scene
	print("Scene loaded: ", cur_scene.name)
	if params:
		for key in params:
			var val = params[key]
			print(key, ": ", val)

# Called after the graphic transition ends
func start():
	print("gameplay.gd: start() called")
