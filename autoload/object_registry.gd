# Creates, maintains, and organizes spawned special effects or projectiles; 
# objects that should be untied from their spawners' lifespan when freed.
extends Node

@onready var _effects := $Effects
@onready var _projectiles := $Projectiles
@onready var _asteroids := $Asteroids
@onready var _planets = $Planets
@onready var _labels = $Labels


func register_effect(effect: Node) -> void:
	_effects.add_child(effect)


func register_projectile(projectile: Node) -> void:
	_projectiles.add_child(projectile)


func register_asteroid(asteroid: Node) -> void:
	_asteroids.add_child(asteroid)


func register_planet(planet: Node) -> void:
	_planets.add_child(planet)


func register_label(label: Node) -> void:
	_labels.add_child(label)
