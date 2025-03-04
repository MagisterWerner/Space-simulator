extends Node2D

var FCT = preload("res://UI/FCT.tscn")

@export var travel = Vector2(0, -80)
@export var duration = 1
@export var spread = PI/2


func show_value(target, value, crit=false):
	var fct = FCT.instantiate()
	var ship_coords = Vector2(target.position.x-30, target.position.y-30)
	add_child(fct)
	fct.set_position(ship_coords)
	fct.show_value(str(value), travel, duration, spread, crit)
