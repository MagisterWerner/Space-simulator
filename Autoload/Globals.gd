# Autoloaded singleton that preloards important resources upon game start

extends Node

@export var world_seed = 1
@export var random_seed = false


################################################################################
# Exported variables that can be changed from the Inspector in the editor
################################################################################
@export var sector_size: = Vector2(1024,1024)
@export_range(10, 100, 10) var sector_number: int = 50
#@export var grid_color: Color = "white"
#@export var planets: int = 4   # Replace with desired max number (set in inspector)
#@export var world_seed: int = 1
#@export var max_asteroids: int = 5  # Replace with desired max number (set in inspector)
################################################################################



# VARIABLES
var first_run = true
var node_player
var node_camera
var node_target


# MUSIC
#@export var music_spotted := preload("res://Resources/Music/Spotted.ogg")
#@export var music_safety := preload("res://Resources/Music/Safety2.ogg")


# SCENES
@export var scene_asteroid_large: PackedScene
@export var scene_asteroid_medium: PackedScene
@export var scene_asteroid_small: PackedScene

# Game objects that the player can interact and trade with
@export var PlanetArid: PackedScene
@export var PlanetFrozen: PackedScene
@export var PlanetHumid: PackedScene
@export var PlanetVolcanic: PackedScene


# SFX
#const sfx_thruster = preload("res://Resources/Sounds/thrusterFire_002.ogg")
#const sfx_explosion = preload("res://Resources/Sounds/mixkit-distant-war-explosions-1696.wav")
#const sfx_missile = preload("res://Resources/Sounds/missile.sfxr")
#const sfx_laser = preload("res://Resources/Sounds/laser.sfxr")


# SPRITES
const sprite_asteroid_s1 := preload("res://assets/sprites/asteroids/asteroid_small_1.png")
const sprite_asteroid_s2 := preload("res://assets/sprites/asteroids/asteroid_small_2.png")
const sprite_asteroid_s3 := preload("res://assets/sprites/asteroids/asteroid_small_3.png")
const sprite_asteroid_s4 := preload("res://assets/sprites/asteroids/asteroid_small_4.png")
const sprite_asteroid_s5 := preload("res://assets/sprites/asteroids/asteroid_small_5.png")
const sprite_asteroid_m1 := preload("res://assets/sprites/asteroids/asteroid_medium_1.png")
const sprite_asteroid_m2 := preload("res://assets/sprites/asteroids/asteroid_medium_2.png")
const sprite_asteroid_m3 := preload("res://assets/sprites/asteroids/asteroid_medium_3.png")
const sprite_asteroid_m4 := preload("res://assets/sprites/asteroids/asteroid_medium_4.png")
const sprite_asteroid_m5 := preload("res://assets/sprites/asteroids/asteroid_medium_5.png")
const sprite_asteroid_l1 := preload("res://assets/sprites/asteroids/asteroid_large_1.png")
const sprite_asteroid_l2 := preload("res://assets/sprites/asteroids/asteroid_large_2.png")
const sprite_asteroid_l3 := preload("res://assets/sprites/asteroids/asteroid_large_3.png")
const sprite_asteroid_l4 := preload("res://assets/sprites/asteroids/asteroid_large_4.png")
const sprite_asteroid_l5 := preload("res://assets/sprites/asteroids/asteroid_large_5.png")


# FUNCTIONS
func _ready():
	randomize()
