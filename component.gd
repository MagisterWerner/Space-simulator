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

func _ready() -> void:
	await owner.ready
	owner_entity = owner
	setup()
	if enabled:
		enable()
	component_ready.emit()

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
