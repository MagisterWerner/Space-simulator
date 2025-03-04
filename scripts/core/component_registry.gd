# component_registry.gd
extends Node

static func get_component(entity: Node, component_type: String) -> Node:
	if entity.has_node(component_type):
		return entity.get_node(component_type)
	return null
