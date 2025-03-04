# Autoloaded singleton that preloards important resources upon game start

extends Node

# VARIABLES
var first_run = true
var node_player
var node_camera
var node_target


# MUSIC
#@export var music_spotted := preload("res://Resources/Music/Spotted.ogg")
#@export var music_safety := preload("res://Resources/Music/Safety2.ogg")


# SCENES
@export var scene_damage_numbers := preload("res://UI/FCTMgr.tscn")
@export var scene_explosion := preload("res://VFX/RetroExplosion.tscn")
@export var scene_laser := preload("res://Weapons/Laser.tscn")
@export var scene_enemy_laser := preload("res://Weapons/EnemyLaser.tscn")
@export var scene_missile := preload("res://Weapons/Missile.tscn")
@export var scene_enemy_missile := preload("res://Weapons/EnemyMissile.tscn")
@export var scene_asteroid_large: PackedScene = preload("res://Objects/Asteroids/AsteroidLarge.tscn")
@export var scene_asteroid_medium: PackedScene = preload("res://Objects/Asteroids/AsteroidMedium.tscn")
@export var scene_asteroid_small: PackedScene = preload("res://Objects/Asteroids/AsteroidSmall.tscn")

   # Game objects that the player can interact and trade with
@export var PlanetArid: PackedScene = preload("res://Objects/Planets/HomePlanetArid.tscn")
@export var PlanetFrozen: PackedScene = preload("res://Objects/Planets/HomePlanetFrozen.tscn")
@export var PlanetHumid: PackedScene = preload("res://Objects/Planets/HomePlanetHumid.tscn")
@export var PlanetVolcanic: PackedScene = preload("res://Objects/Planets/HomePlanetVolcanic.tscn")
@export var CapitalShip: PackedScene = preload("res://Objects/Vessels/CapitalShip.tscn")


# SFX
#const sfx_thruster = preload("res://Resources/Sounds/thrusterFire_002.ogg")
#const sfx_explosion = preload("res://Resources/Sounds/mixkit-distant-war-explosions-1696.wav")
#const sfx_missile = preload("res://Resources/Sounds/missile.sfxr")
#const sfx_laser = preload("res://Resources/Sounds/laser.sfxr")


# SPRITES
const sprite_asteroid_s1 := preload("res://Resources/Images/Asteroids/AsteroidS1.png")
const sprite_asteroid_s2 := preload("res://Resources/Images/Asteroids/AsteroidS2.png")
const sprite_asteroid_s3 := preload("res://Resources/Images/Asteroids/AsteroidS3.png")
const sprite_asteroid_s4 := preload("res://Resources/Images/Asteroids/AsteroidS4.png")
const sprite_asteroid_s5 := preload("res://Resources/Images/Asteroids/AsteroidS5.png")
const sprite_asteroid_m1 := preload("res://Resources/Images/Asteroids/AsteroidM1.png")
const sprite_asteroid_m2 := preload("res://Resources/Images/Asteroids/AsteroidM2.png")
const sprite_asteroid_m3 := preload("res://Resources/Images/Asteroids/AsteroidM3.png")
const sprite_asteroid_m4 := preload("res://Resources/Images/Asteroids/AsteroidM4.png")
const sprite_asteroid_m5 := preload("res://Resources/Images/Asteroids/AsteroidM5.png")
const sprite_asteroid_l1 := preload("res://Resources/Images/Asteroids/AsteroidL1.png")
const sprite_asteroid_l2 := preload("res://Resources/Images/Asteroids/AsteroidL2.png")
const sprite_asteroid_l3 := preload("res://Resources/Images/Asteroids/AsteroidL3.png")
const sprite_asteroid_l4 := preload("res://Resources/Images/Asteroids/AsteroidL4.png")
const sprite_asteroid_l5 := preload("res://Resources/Images/Asteroids/AsteroidL5.png")


# FUNCTIONS
func _ready():
	randomize()
