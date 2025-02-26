class_name EnemyStateBase
extends Node

# Reference to the enemy node
var enemy: Node2D

func _ready():
	# Ensure this state is disabled initially
	set_process(false)
	set_physics_process(false)

# Called when entering this state
func enter():
	set_process(true)
	set_physics_process(true)

# Called when exiting this state
func exit():
	set_process(false)
	set_physics_process(false)

# Process logic for this state (can be overridden by child states)
func process(_delta):
	pass

# Physics process for this state (can be overridden by child states)
func physics_process(_delta):
	pass