extends Node

# This is an autoload script that ensures components are loaded in the correct order.
# Add this to your project's autoload list with the name "ComponentRegistry"

func _ready():
	# This script doesn't need to do anything.
	# Its purpose is to ensure component scripts are loaded in a predictable order.
	pass

# Helper function to get a component from an entity
static func get_component(entity: Node, component_type: String) -> Node:
	if entity.has_node(component_type):
		return entity.get_node(component_type)
	return null
