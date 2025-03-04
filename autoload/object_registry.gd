# object_registry.gd
extends Node

var _projectiles: Node
var _effects: Node

func _ready():
	var projectiles = Node.new()
	projectiles.name = "Projectiles"
	add_child(projectiles)
	_projectiles = projectiles
	
	var effects = Node.new()
	effects.name = "Effects"
	add_child(effects)
	_effects = effects
