# scripts/strategies/strategy.gd
extends Resource
class_name Strategy

# Base signals for all strategies
signal strategy_enabled(strategy_name, property_name, value)
signal strategy_disabled(strategy_name, property_name)

# Strategy identification
var strategy_name: String = "Generic Strategy"
var description: String = "A strategy that can be applied to components"
var icon_path: String = ""
var price: int = 100

# Target component information
var target_component_type: String = ""
var affected_properties: Array = []

# State
var is_active: bool = false
var target_component = null

# Apply strategy to a component
func apply(component) -> bool:
	if not can_apply_to(component):
		return false
		
	target_component = component
	is_active = true
	
	_modify_component()
	strategy_enabled.emit(strategy_name, get_affected_property(), get_property_value())
	
	return true

# Remove strategy from component
func remove() -> bool:
	if not is_active or target_component == null:
		return false
		
	_restore_component()
	
	strategy_disabled.emit(strategy_name, get_affected_property())
	
	is_active = false
	target_component = null
	
	return true

# Get the name of the property this strategy affects
func get_affected_property() -> String:
	if affected_properties.size() > 0:
		return affected_properties[0]
	return ""

# Get the value this strategy applies to the property
func get_property_value():
	# Override in subclasses
	return null

# Check if strategy can be applied to a component
func can_apply_to(component) -> bool:
	# Base implementation just checks if component is valid
	return component != null

# Virtual method to modify the component
# Override in subclasses
func _modify_component() -> void:
	pass

# Virtual method to restore the component to its original state
# Override in subclasses
func _restore_component() -> void:
	pass

# Get strategy info for UI display
func get_info() -> Dictionary:
	return {
		"name": strategy_name,
		"description": description,
		"icon": icon_path,
		"price": price,
		"target": target_component_type
	}
