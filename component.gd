# component.gd
extends Node
class_name Component

# Base component class that all components will inherit from
# Components add functionality to entities in a modular way

signal component_ready
signal component_disabled
signal component_enabled

@export var enabled: bool = true
@export var debug_mode: bool = false

var owner_entity: Node = null
# Global init tracking for all components - static dictionary persists across component instances
static var _init_registry = {}

func _ready() -> void:
	await owner.ready
	owner_entity = owner
	_initialize()
	if enabled:
		enable()
	component_ready.emit()

# New private initialization sequence
func _initialize() -> void:
	# Generate unique identifier for this component instance
	var instance_id = get_instance_id()
	
	# If this specific component instance has been initialized, skip
	if _init_registry.has(instance_id):
		return
		
	# Mark this instance as initialized
	_init_registry[instance_id] = true
	
	# Call the setup method which subclasses will override
	setup()
	
	# Clean up registry occasionally to prevent memory leaks from deleted components
	if _init_registry.size() > 100:  # Arbitrary threshold
		_cleanup_registry()

# Cleanup function to prevent memory buildup
func _cleanup_registry() -> void:
	var valid_ids = []
	for id in _init_registry.keys():
		if is_instance_valid(instance_from_id(id)):
			valid_ids.append(id)
	
	# Rebuild registry with only valid instances
	var new_registry = {}
	for id in valid_ids:
		new_registry[id] = true
	_init_registry = new_registry

# Interface method to be overridden by child classes
func setup() -> void:
	# Override this in child components to setup the component
	pass

func enable() -> void:
	if not enabled:
		enabled = true
		_on_enable()
		component_enabled.emit()
		
func disable() -> void:
	if enabled:
		enabled = false
		_on_disable()
		component_disabled.emit()

func _on_enable() -> void:
	# Override this in child components when component is enabled
	pass
	
func _on_disable() -> void:
	# Override this in child components when component is disabled
	pass
	
func _process(delta: float) -> void:
	if enabled:
		process_component(delta)
		
func _physics_process(delta: float) -> void:
	if enabled:
		physics_process_component(delta)
		
func process_component(_delta: float) -> void:
	# Override this in child components for custom process logic
	pass
	
func physics_process_component(_delta: float) -> void:
	# Override this in child components for custom physics process logic
	pass
	
func debug_print(message: String) -> void:
	if debug_mode:
		print("[Component:%s] %s" % [name, message])
