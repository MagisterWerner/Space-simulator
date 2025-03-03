extends Node
class_name ResourceManager

# Preload scenes
var laser_scene = preload("res://scenes/laser.tscn")
var player_scene = preload("res://scenes/player.tscn")
var enemy_scene = preload("res://scenes/enemy.tscn")

# Keep track of resource load status
var resources_loaded = false

func _ready():
	# Load all resources when the manager is added to the scene
	call_deferred("load_all_resources")

# Function to load all game resources
func load_all_resources():
	if resources_loaded:
		return
	
	print("ResourceManager: Loading all game resources...")
	
	# Load ship sprites
	load_ship_sprites()
	
	resources_loaded = true
	print("ResourceManager: All resources loaded successfully!")

# Function to load ship sprites
func load_ship_sprites():
	# Load player ship sprites
	var player_ship_sprites = []
	
	# Try to load player_ship_1.png which we know exists
	var texture = load("res://sprites/ships_player/player_ship_1.png")
	if texture:
		player_ship_sprites.append(texture)
	
	# Try to load others, but don't report errors if missing
	for i in range(2, 4):  # player_ship_2.png to player_ship_3.png
		var path = "res://sprites/ships_player/player_ship_" + str(i) + ".png"
		if ResourceLoader.exists(path):
			texture = load(path)
			if texture:
				player_ship_sprites.append(texture)
	
	print("ResourceManager: Loaded " + str(player_ship_sprites.size()) + " player ship sprites")
	
	# Load enemy ship sprites
	var enemy_ship_sprites = []
	
	# Try to load enemy_ship_1.png which we know exists
	texture = load("res://sprites/ships_enemy/enemy_ship_1.png")
	if texture:
		enemy_ship_sprites.append(texture)
	
	# Try to load others, but don't report errors if missing
	for i in range(2, 4):  # enemy_ship_2.png to enemy_ship_3.png
		var path = "res://sprites/ships_enemy/enemy_ship_" + str(i) + ".png"
		if ResourceLoader.exists(path):
			texture = load(path)
			if texture:
				enemy_ship_sprites.append(texture)
	
	print("ResourceManager: Loaded " + str(enemy_ship_sprites.size()) + " enemy ship sprites")

# Create a new laser instance
func create_laser(is_player_laser: bool = false):
	var laser = laser_scene.instantiate()
	return laser

# Create a new enemy instance
func create_enemy():
	return enemy_scene.instantiate()

# Create a new player instance
func create_player():
	return player_scene.instantiate()
