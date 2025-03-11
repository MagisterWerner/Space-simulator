# autoload/service_locator.gd
# ===========================
# Purpose:
#   Central service locator for dependency injection.
#   Manages registration and resolution of services.
#   Ensures proper initialization order and dependency management.

extends Node

signal service_registered(service_name, service)
signal service_initialized(service_name)
signal all_services_initialized

# Store registered services
var _services: Dictionary = {}

# Track initialization status
var _initialized_services: Dictionary = {}
var _dependency_graph: Dictionary = {}
var _initialization_order: Array = []
var _all_initialized: bool = false

# Initialization flags
var _service_locator_ready: bool = false

# Static accessor for the ServiceLocator instance
static func get_instance() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("/root/ServiceLocator")

func _ready() -> void:
	# Set process mode to continue during pause
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Signal when this service locator is ready
	_service_locator_ready = true
	
	# Auto-register all autoloads that exist at startup
	call_deferred("_auto_register_autoloads")

# Automatically register all autoloads in the scene tree
func _auto_register_autoloads() -> void:
	# Give one frame for all autoloads to be added to the scene
	await get_tree().process_frame
	
	var autoloads = []
	
	# Find all direct children of /root that aren't the main scene
	var root = get_tree().root
	var main_scene = get_tree().current_scene
	
	for i in range(root.get_child_count()):
		var node = root.get_child(i)
		if node != main_scene and node != self:
			autoloads.append(node)
	
	# Register each autoload found
	for autoload in autoloads:
		var service_name = autoload.name
		
		# Skip if already registered
		if _services.has(service_name):
			continue
			
		register_service(service_name, autoload)
		
		print("ServiceLocator: Auto-registered %s" % service_name)
	
	# After all services are registered, initialize them in dependency order
	_initialize_services()

# Register a service with the locator
func register_service(service_name: String, service: Object) -> void:
	if _services.has(service_name):
		push_warning("ServiceLocator: Service %s is already registered" % service_name)
		return
	
	_services[service_name] = service
	_initialized_services[service_name] = false
	
	service_registered.emit(service_name, service)
	
	if service.has_method("get_dependencies"):
		var dependencies = service.get_dependencies()
		_dependency_graph[service_name] = dependencies
	else:
		_dependency_graph[service_name] = []
	
	print("ServiceLocator: Registered service %s" % service_name)

# Register a service with explicit dependencies
func register_with_dependencies(service_name: String, service: Object, dependencies: Array) -> void:
	register_service(service_name, service)
	_dependency_graph[service_name] = dependencies

# Get a service from the locator
func get_service(service_name: String) -> Object:
	if not _services.has(service_name):
		push_warning("ServiceLocator: Service %s not found" % service_name)
		return null
	
	return _services[service_name]

# Check if a service is registered
func has_service(service_name: String) -> bool:
	return _services.has(service_name)

# Check if a service is initialized
func is_service_initialized(service_name: String) -> bool:
	if not _initialized_services.has(service_name):
		return false
	
	return _initialized_services[service_name]

# Check if all services are initialized
func are_all_services_initialized() -> bool:
	return _all_initialized

# Get the initialization order of services
func get_initialization_order() -> Array:
	return _initialization_order

# Wait for a service to be registered and initialized
func wait_for_service(service_name: String) -> Object:
	if has_service(service_name) and is_service_initialized(service_name):
		return get_service(service_name)
	
	# Wait for the service to be registered and initialized
	while not has_service(service_name) or not is_service_initialized(service_name):
		await get_tree().process_frame
	
	return get_service(service_name)

# Initialize services in dependency order
func _initialize_services() -> void:
	# Determine initialization order based on dependencies
	var ordered_services = _determine_initialization_order()
	
	# Debug output
	print("ServiceLocator: Initializing services in order:")
	for service_name in ordered_services:
		print("  - %s" % service_name)
	
	# Initialize each service in order
	for service_name in ordered_services:
		var service = _services[service_name]
		
		# Check if service has an initialization method
		if service.has_method("initialize_service"):
			service.initialize_service()
		
		_initialized_services[service_name] = true
		_initialization_order.append(service_name)
		
		print("ServiceLocator: Initialized service %s" % service_name)
		service_initialized.emit(service_name)
	
	# Mark all services as initialized
	_all_initialized = true
	all_services_initialized.emit()
	
	print("ServiceLocator: All services initialized")

# Determine the proper initialization order based on dependencies
func _determine_initialization_order() -> Array:
	var ordered_services = []
	var processed = {}
	
	# Initialize all services as not processed
	for service_name in _services.keys():
		processed[service_name] = false
	
	# Process each service
	for service_name in _services.keys():
		_visit_node(service_name, processed, ordered_services)
	
	return ordered_services

# Depth-first search to determine initialization order
func _visit_node(node: String, processed: Dictionary, ordered_services: Array) -> void:
	# If already processed, skip
	if processed[node]:
		return
	
	# Mark as being processed (to detect cycles)
	processed[node] = true
	
	# Process dependencies first
	for dependency in _dependency_graph[node]:
		if not _services.has(dependency):
			push_warning("ServiceLocator: Missing dependency %s for service %s" % [dependency, node])
			continue
			
		_visit_node(dependency, processed, ordered_services)
	
	# Add this node to the ordered list
	ordered_services.append(node)

# For debugging: Print the dependency graph
func print_dependency_graph() -> void:
	print("ServiceLocator: Dependency Graph:")
	for service_name in _dependency_graph.keys():
		var dependencies = _dependency_graph[service_name]
		print("  %s depends on: %s" % [service_name, dependencies])
