# globals.gd
extends Node

var size: Vector2

func _ready():
	size = get_viewport().get_visible_rect().size

func set(property, value):
	if property == "node_player":
		pass
