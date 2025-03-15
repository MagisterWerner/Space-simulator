# scripts/components/component.gd - Optimized Base Component Class
extends Node
class_name Component

signal component_ready
signal component_disabled
signal component_enabled
signal property_changed(property_name, old_value, new_value)

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
var _logger = null

func depends_on(component: Component) -> void:
	if component and not _dependencies.has(component):
		_dependencies.append(component)
		component._dependents.append(self)

func are_dependencies_met() -> bool:
	for dependency in _dependencies:
		if not is_instance_valid(dependency) or not dependency.enabled:
			return false
	return true

func _ready() -> void:
	# Get logger reference
	if Engine.has_singleton("Logger"):
		_logger = Engine.get_singleton("Logger")
	
	# Handle debug settings
	_setup_debug_settings()
	
	# Wait for owner to be ready
	await owner.ready
	owner_entity = owner
	
	if not _initialized:
		_initialized = true
		setup()
	
	if enabled:
		enable()
	
	component_ready.emit()
	
	if debug_mode:
		_debug_print("Component initialized on " + owner.name)

func _setup_debug_settings() -> void:
	var game_settings = get_node_or_null("/root/GameSettings")
	if game_settings:
		# Set initial debug state
		debug_mode = game_settings.debug_mode and game_settings.debug_components
		
		# Connect to debug settings changes
		if not game_settings.is_connected("debug_settings_changed", _on_debug_settings_changed):
			game_settings.connect("debug_settings_changed", _on_debug_settings_changed)

func _on_debug_settings_changed(debug_settings: Dictionary) -> void:
	debug_mode = debug_settings.get("master", false) and debug_settings.get("components", false)

func enable() -> void:
	if are_dependencies_met():
		enabled = true
	elif _logger:
		_logger.warning(name, "Cannot enable component - dependencies not met")

func disable() -> void:
	enabled = false
	
	# Notify dependents
	for dependent in _dependents:
		if dependent.enabled and not dependent.are_dependencies_met():
			dependent.disable()

# Virtual methods to override
func setup() -> void:
	pass

func _on_enable() -> void:
	pass
	
func _on_disable() -> void:
	pass
	
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

func _debug_print(message: String) -> void:
	if debug_mode:
		if _logger:
			_logger.debug(name, message)
		else:
			print("[Component:%s] %s" % [name, message])

func set_property(property_name: String, value) -> void:
	if has_property(self, property_name):
		var old_value = get(property_name)
		# Only emit signal if value actually changes
		if old_value != value:
			set(property_name, value)
			property_changed.emit(property_name, old_value, value)
			
			if debug_mode:
				_debug_print("Property changed: " + property_name + 
					" from " + str(old_value) + " to " + str(value))

# Cache property lists to avoid repeated introspection
static var _property_cache = {}

static func has_property(object: Object, property_name: String) -> bool:
	var obj_id = object.get_instance_id()
	
	# Check cache first
	if _property_cache.has(obj_id):
		return property_name in _property_cache[obj_id]
	
	# Build cache for this object type
	var properties = []
	for property in object.get_property_list():
		properties.append(property.name)
	
	_property_cache[obj_id] = properties
	return property_name in properties
