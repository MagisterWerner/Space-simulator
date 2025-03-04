# gameplay.gd
extends Node2D

@onready var player_ship = $PlayerShip/Ship

func _ready():
	player_ship.position = Vector2(640, 360)

func pre_start(params = null):
	var cur_scene = get_tree().current_scene
	print("Scene loaded: ", cur_scene.name)
	if params:
		for key in params:
			var val = params[key]
			print(key, ": ", val)

func start():
	pass
