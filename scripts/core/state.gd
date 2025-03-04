# state.gd
class_name State
extends Node

var state_machine = null
var entity = null

var process_enabled = true
var physics_process_enabled = true
var input_processing_enabled = true

func _ready():
	set_process(false)
	set_physics_process(false)

func initialize(sm, e):
	state_machine = sm
	entity = e
	
func enter():
	set_process(process_enabled)
	set_physics_process(physics_process_enabled)

func exit():
	set_process(false)
	set_physics_process(false)

func handle_input(_event):
	pass

func process(_delta):
	pass

func physics_process(_delta):
	pass

func get_transition():
	return ""

func is_enabled():
	return true
