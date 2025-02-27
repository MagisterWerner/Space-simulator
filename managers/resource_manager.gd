class_name ResourceManager
extends Node

# Arrays to store preloaded resources
var planet_sprites = []
var moon_sprites = []
var asteroid_sprites = {
	"large": [],
	"medium": [],
	"small": []
}
var player_ship_sprites = []
var enemy_ship_sprites = []
var weapon_sprites = {
	"laser_blue": null,
	"laser_red": null
}

# Preload scenes
var laser_scene = preload("res://laser.tscn")
var player_scene = preload("res://player.tscn")
var enemy_scene = preload("res://enemy.tscn")

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
	
	# Load planet sprites
	load_planet_sprites()
	
	# Load moon sprites
	load_moon_sprites()
	
	# Load asteroid sprites
	load_asteroid_sprites()
	
	# Load ship sprites
	load_ship_sprites()
	
	# Load weapon sprites
	load_weapon_sprites()
	
	resources_loaded = true
	print("ResourceManager: All resources loaded successfully!")

# Function to load planet sprites
func load_planet_sprites():
	planet_sprites.clear()
	
	var planet_paths = [
		"res://sprites/planets/planet_1.png",
		"res://sprites/planets/planet_2.png",
		"res://sprites/planets/planet_3.png",
		"res://sprites/planets/planet_4.png",
		"res://sprites/planets/planet_5.png"
	]
	
	for path in planet_paths:
		var texture = load(path)
		if texture:
			planet_sprites.append(texture)
		else:
			push_warning("ResourceManager: Failed to load planet sprite: " + path)
	
	print("ResourceManager: Loaded " + str(planet_sprites.size()) + " planet sprites")
	
	# Create fallback if no sprites loaded
	if planet_sprites.size() == 0:
		create_fallback_planet_texture()

# Create a fallback planet texture if none can be loaded
func create_fallback_planet_texture():
	print("ResourceManager: Creating fallback planet texture")
	var image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for x in range(64):
		for y in range(64):
			var dist = Vector2(x - 32, y - 32).length()
			if dist < 30:
				image.set_pixel(x, y, Color(1, 1, 1, 1))
	var fallback_texture = ImageTexture.create_from_image(image)
	planet_sprites.append(fallback_texture)

# Function to load moon sprites
func load_moon_sprites():
	moon_sprites.clear()
	
	var moon_paths = [
		"res://sprites/moons/moon_1.png",
		"res://sprites/moons/moon_2.png",
		"res://sprites/moons/moon_3.png"
	]
	
	for path in moon_paths:
		var texture = load(path)
		if texture:
			moon_sprites.append(texture)
		else:
			push_warning("ResourceManager: Failed to load moon sprite: " + path)
	
	print("ResourceManager: Loaded " + str(moon_sprites.size()) + " moon sprites")
	
	# Create fallback if no sprites loaded
	if moon_sprites.size() == 0:
		create_fallback_moon_texture()

# Create a fallback moon texture if none can be loaded
func create_fallback_moon_texture():
	print("ResourceManager: Creating fallback moon texture")
	var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for x in range(32):
		for y in range(32):
			var dist = Vector2(x - 16, y - 16).length()
			if dist < 14:
				image.set_pixel(x, y, Color(0.9, 0.9, 0.9, 1))
	var fallback_texture = ImageTexture.create_from_image(image)
	moon_sprites.append(fallback_texture)

# Function to load asteroid sprites
func load_asteroid_sprites():
	# Clear existing sprites
	asteroid_sprites.large.clear()
	asteroid_sprites.medium.clear()
	asteroid_sprites.small.clear()
	
	# Load large asteroid sprites
	for i in range(1, 6):  # 1 to 5
		var path = "res://sprites/asteroids/asteroid_large_" + str(i) + ".png"
		var texture = load(path)
		if texture:
			asteroid_sprites.large.append(texture)
		else:
			push_warning("ResourceManager: Failed to load asteroid sprite: " + path)
	
	# Load medium asteroid sprites
	for i in range(1, 6):  # 1 to 5
		var path = "res://sprites/asteroids/asteroid_medium_" + str(i) + ".png"
		var texture = load(path)
		if texture:
			asteroid_sprites.medium.append(texture)
		else:
			push_warning("ResourceManager: Failed to load asteroid sprite: " + path)
	
	# Load small asteroid sprites
	for i in range(1, 6):  # 1 to 5
		var path = "res://sprites/asteroids/asteroid_small_" + str(i) + ".png"
		var texture = load(path)
		if texture:
			asteroid_sprites.small.append(texture)
		else:
			push_warning("ResourceManager: Failed to load asteroid sprite: " + path)
	
	print("ResourceManager: Loaded asteroid sprites: ", 
		asteroid_sprites.large.size(), " large, ", 
		asteroid_sprites.medium.size(), " medium, ", 
		asteroid_sprites.small.size(), " small")

# Function to load ship sprites
func load_ship_sprites():
	# Load player ship sprites
	player_ship_sprites.clear()
	for i in range(1, 4):  # Assuming player_ship_1.png, player_ship_2.png, etc.
		var path = "res://sprites/ships_player/player_ship_" + str(i) + ".png"
		var texture = load(path)
		if texture:
			player_ship_sprites.append(texture)
	
	print("ResourceManager: Loaded " + str(player_ship_sprites.size()) + " player ship sprites")
	
	# Load enemy ship sprites
	enemy_ship_sprites.clear()
	for i in range(1, 4):  # Assuming enemy_ship_1.png, enemy_ship_2.png, etc.
		var path = "res://sprites/ships_enemy/enemy_ship_" + str(i) + ".png"
		var texture = load(path)
		if texture:
			enemy_ship_sprites.append(texture)
	
	print("ResourceManager: Loaded " + str(enemy_ship_sprites.size()) + " enemy ship sprites")

# Function to load weapon sprites
func load_weapon_sprites():
	# Load laser sprites
	weapon_sprites.laser_blue = load("res://sprites/weapons/laser_blue.png")
	weapon_sprites.laser_red = load("res://sprites/weapons/laser_red.png")
	
	# Count loaded weapon sprites
	var count = 0
	for key in weapon_sprites:
		if weapon_sprites[key] != null:
			count += 1
	
	print("ResourceManager: Loaded " + str(count) + " weapon sprites")

# Get a single planet sprite by index
func get_planet_sprite(index: int):
	if planet_sprites.size() > 0:
		return planet_sprites[index % planet_sprites.size()]
	return null

# Get a single moon sprite by index
func get_moon_sprite(index: int):
	if moon_sprites.size() > 0:
		return moon_sprites[index % moon_sprites.size()]
	return null

# Get an asteroid sprite by size and index
func get_asteroid_sprite(size: String, index: int):
	if asteroid_sprites.has(size) and asteroid_sprites[size].size() > 0:
		return asteroid_sprites[size][index % asteroid_sprites[size].size()]
	return null

# Get a ship sprite for player or enemy
func get_ship_sprite(is_player: bool, index: int = 0):
	if is_player and player_ship_sprites.size() > 0:
		return player_ship_sprites[index % player_ship_sprites.size()]
	elif not is_player and enemy_ship_sprites.size() > 0:
		return enemy_ship_sprites[index % enemy_ship_sprites.size()]
	return null

# Get a weapon sprite
func get_weapon_sprite(type: String):
	if weapon_sprites.has(type):
		return weapon_sprites[type]
	return null

# Create a new laser instance
func create_laser(is_player_laser: bool = false):
	var laser = laser_scene.instantiate()
	
	# Configure the laser color based on player/enemy
	var sprite = laser.get_node_or_null("Sprite2D")
	if sprite:
		if is_player_laser:
			sprite.texture = weapon_sprites.laser_blue
		else:
			sprite.texture = weapon_sprites.laser_red
	
	return laser

# Create a new enemy instance
func create_enemy():
	return enemy_scene.instantiate()

# Create a new player instance
func create_player():
	return player_scene.instantiate()
