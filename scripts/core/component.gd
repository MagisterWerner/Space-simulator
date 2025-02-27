class_name Component
extends Node

# Owner entity that this component belongs to
var entity = null

# Called when the node enters the scene tree
func _ready():
	# Get the entity (parent node)
	entity = get_parent()
	_initialize()

# Virtual method for component initialization
func _initialize():
	pass

# Virtual method for component cleanup
func _cleanup():
	pass

# Enable/disable the component
func set_active(active: bool):
	set_process(active)
	set_physics_process(active)
