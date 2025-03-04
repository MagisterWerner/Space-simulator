# main.gd
extends Node2D

@onready var player_ship = $PlayerShip
@onready var camera = $Camera2D

var screen_size: Vector2

func _ready() -> void:
	screen_size = get_viewport_rect().size
	player_ship.position = screen_size / 2
	camera.position = player_ship.position

func _process(_delta: float) -> void:
	camera.position = player_ship.position
