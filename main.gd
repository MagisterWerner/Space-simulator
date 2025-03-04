# main.gd
extends Node2D

@onready var player_ship = $PlayerShip
@onready var camera = $Camera2D

var screen_size: Vector2

func _ready() -> void:
	screen_size = get_viewport_rect().size
	player_ship.position = screen_size / 2
	camera.position = player_ship.position
	
	player_ship.connect("player_destroyed", _on_player_destroyed)

func _process(_delta: float) -> void:
	camera.position = player_ship.position

func _on_player_destroyed() -> void:
	get_tree().create_timer(2.0).timeout.connect(func(): get_tree().reload_current_scene())
