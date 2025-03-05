# scripts/components/component.gd - Improvements to base Component class

extends Node
class_name Component

signal component_ready
signal component_disabled
signal component_enabled
signal property_changed(property_name, old_value, new_value)

# Constants for component categories
enum ComponentCategory {
	HEALTH,
	MOVEMENT,
	WEAPON,
	SHIELD,
	SENSOR,
	UTILITY
}

@export var enabled: bool = true:
	set(value):
		if enabled != value:
			enabled = value
			if enabled:
				_on_enable()
				component_enabled.emit()
			else:
				_on_disable()
				component_disabled.emit()

@export var debug_mode: bool = false
@export var category: ComponentCategory = ComponentCategory.UTILITY
@export var priority: int = 0  # For processing order

var owner_entity: Node = null
var _initialized: bool = false
var _dependencies: Array[Component] = []
var _dependents: Array[Component] = []
var _logger = null  # Will be set to DebugLogger instance

# Register a dependency on another component
func depends_on(component: Component) -> void:
	if component and not _dependencies.has(component):
		_dependencies.append(component)
		component._dependents.append(self)

# Check if all dependencies are satisfied
func are_dependencies_met() -> bool:
	for dependency in _dependencies:
		if not is_instance_valid(dependency) or not dependency.enabled:
			return false
	return true

# This function replaces the old _initialize
func _ready() -> void:
	# Get logger from autoload if available
	if Engine.has_singleton("Logger"):
		_logger = Engine.get_singleton("Logger")
	
	await owner.ready
	owner_entity = owner
	
	if not _initialized:
		_initialized = true
		setup()
	
	if enabled:
		enable()
	
	component_ready.emit()
	
	# Log component initialization
	if debug_mode and _logger:
		_logger.debug(name, "Component initialized on " + owner.name)

# Cleaner enable/disable functions
func enable() -> void:
	if are_dependencies_met():
		enabled = true
	else:
		if _logger:
			_logger.warning(name, "Cannot enable component - dependencies not met")

func disable() -> void:
	enabled = false
	
	# Notify dependents that they may need to disable
	for dependent in _dependents:
		if dependent.enabled and not dependent.are_dependencies_met():
			if _logger:
				_logger.info(name, "Disabling dependent component: " + dependent.name)
			dependent.disable()

# ---- Virtual methods to override ----

# Called once during initialization
func setup() -> void:
	pass

# Called when the component is enabled
func _on_enable() -> void:
	pass
	
# Called when the component is disabled
func _on_disable() -> void:
	pass
	
# Process functions
func _process(delta: float) -> void:
	if enabled:
		process_component(delta)
		
func _physics_process(delta: float) -> void:
	if enabled:
		physics_process_component(delta)
		
func process_component(_delta: float) -> void:
	pass
	
func physics_process_component(_delta: float) -> void:
	pass

# Clean debug logging
func debug_print(message: String) -> void:
	if debug_mode:
		if _logger:
			_logger.debug(name, message)
		else:
			print("[Component:%s] %s" % [name, message])

# Safe property changes with signals
func set_property(property_name: String, value) -> void:
	if has_property(self, property_name):
		var old_value = get(property_name)
		set(property_name, value)
		property_changed.emit(property_name, old_value, value)
		
		if debug_mode and _logger:
			_logger.verbose(name, "Property changed: " + property_name + 
				" from " + str(old_value) + " to " + str(value))

# Helper method to check if an object has a property
static func has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if property.name == property_name:
			return true
	return false
