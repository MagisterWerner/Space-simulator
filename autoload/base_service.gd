# autoload/base_service.gd
# ===========================
# Purpose:
#   Base class for all service managers to standardize the service interface.
#   Provides common functionality for dependency management.

extends Node

# Initialization flag
var _service_initialized: bool = false

# A list of service dependencies
var _dependencies: Array = []

# Get this service's dependencies
# Override this in subclasses
func get_dependencies() -> Array:
	return _dependencies

# Initialize this service
# Override this in subclasses
func initialize_service() -> void:
	_service_initialized = true

# Is this service initialized?
func is_initialized() -> bool:
	return _service_initialized

# Get a dependency by name
func get_dependency(service_name: String) -> Object:
	# Get ServiceLocator directly as node
	var service_locator = get_node_or_null("/root/ServiceLocator")
	if service_locator == null:
		push_error("%s: ServiceLocator not found in scene tree" % name)
		return null
	
	return service_locator.get_service(service_name)

# Check if a dependency exists
func has_dependency(service_name: String) -> bool:
	# Get ServiceLocator directly as node
	var service_locator = get_node_or_null("/root/ServiceLocator")
	if service_locator == null:
		push_error("%s: ServiceLocator not found in scene tree" % name)
		return false
	
	return service_locator.has_service(service_name)

# Connect to a signal on a dependency safely
func connect_to_dependency(service_name: String, signal_name: String, callable: Callable) -> bool:
	var dependency = get_dependency(service_name)
	if not dependency:
		push_warning("%s: Dependency %s not found, couldn't connect to signal %s" % [name, service_name, signal_name])
		return false
	
	if not dependency.has_signal(signal_name):
		push_warning("%s: Signal %s not found on dependency %s" % [name, signal_name, service_name])
		return false
	
	if not dependency.is_connected(signal_name, callable):
		dependency.connect(signal_name, callable)
		
	return true

# Async wait for a dependency to be available
func wait_for_dependency(service_name: String) -> Object:
	# Get ServiceLocator directly as node
	var service_locator = get_node_or_null("/root/ServiceLocator")
	if service_locator == null:
		push_error("%s: ServiceLocator not found in scene tree" % name)
		return null
	
	return await service_locator.wait_for_service(service_name)

# Register this service with the ServiceLocator
func register_self() -> void:
	# Ensure ServiceLocator exists before trying to register
	var service_locator = get_node_or_null("/root/ServiceLocator")
	if service_locator == null:
		# We'll try again later when it might be available
		push_warning("%s: ServiceLocator not found, will retry registration later" % name)
		await get_tree().process_frame
		call_deferred("register_self")
		return
	
	# Register with dependencies
	service_locator.register_with_dependencies(name, self, get_dependencies())
	print("%s: Successfully registered with ServiceLocator" % name)
