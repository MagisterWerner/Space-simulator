# component.gd
class_name Component
extends Node

var entity = null

func _ready():
	entity = get_parent()
	_initialize()

func _initialize():
	pass

func _cleanup():
	pass

func set_active(active: bool):
	set_process(active)
	set_physics_process(active)
