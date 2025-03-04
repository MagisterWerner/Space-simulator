# resource_manager.gd
extends Node
class_name ResourceManager

var laser_scene = preload("res://scenes/laser.tscn")
var player_scene = preload("res://scenes/player.tscn")
var enemy_scene = preload("res://scenes/enemy.tscn")

var player_ship_sprites = []
var enemy_ship_sprites = []
var resources_loaded = false

func _ready():
	call_deferred("load_all_resources")

func load_all_resources():
	if resources_loaded:
		return
	
	load_ship_sprites()
	resources_loaded = true

func load_ship_sprites():
	# Load player ship sprites
	var base_texture = load("res://sprites/ships_player/player_ship_1.png")
	if base_texture:
		player_ship_sprites.append(base_texture)
	
	# Load additional player ships
	for i in range(2, 4):
		var path = "res://sprites/ships_player/player_ship_" + str(i) + ".png"
		if ResourceLoader.exists(path):
			var texture = load(path)
			if texture:
				player_ship_sprites.append(texture)
	
	# Load enemy ship sprites
	base_texture = load("res://sprites/ships_enemy/enemy_ship_1.png")
	if base_texture:
		enemy_ship_sprites.append(base_texture)
	
	# Load additional enemy ships
	for i in range(2, 4):
		var path = "res://sprites/ships_enemy/enemy_ship_" + str(i) + ".png"
		if ResourceLoader.exists(path):
			var texture = load(path)
			if texture:
				enemy_ship_sprites.append(texture)

func create_laser(is_player_laser: bool = false):
	var laser = laser_scene.instantiate()
	return laser

func create_enemy():
	return enemy_scene.instantiate()

func create_player():
	return player_scene.instantiate()
