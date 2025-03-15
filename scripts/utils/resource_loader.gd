# scripts/utils/resource_loader.gd
# Centralized resource management with caching
# This prevents redundant loading of the same resources and improves performance
extends Node
class_name GameResourceLoader

# Resource cache to prevent redundant loading
var _cache: Dictionary = {}
var _loading_status: Dictionary = {}

# Maximum number of cached resources before auto-cleanup
const MAX_CACHE_SIZE: int = 100

# Signal emitted when a resource is loaded
signal resource_loaded(path, resource)
signal cache_cleared()

# Load a resource with caching
# This replaces the problematic preload_resource method
func load_resource(path: String, use_sub_threads: bool = false):
	# Return cached version if available
	if _cache.has(path):
		return _cache[path]
	
	# Check if path exists
	if not ResourceLoader.exists(path):
		push_error("GameResourceLoader: Failed to load resource - path does not exist: " + path)
		return null
	
	# Load the resource and cache it
	var resource = load(path)
	if resource:
		_cache[path] = resource
		resource_loaded.emit(path, resource)
		
		# Clean up cache if it gets too large
		if _cache.size() > MAX_CACHE_SIZE:
			_cleanup_oldest_resources(MAX_CACHE_SIZE / 4)  # Remove 25% of resources
	else:
		push_error("GameResourceLoader: Failed to load resource: " + path)
	
	return resource

# Load resource in background (async)
func load_resource_async(path: String, callback: Callable = Callable()):
	# Return cached version if available
	if _cache.has(path):
		if callback.is_valid():
			callback.call(_cache[path])
		return true
	
	# Check if already being loaded
	if _loading_status.has(path):
		# Add callback to queue
		if callback.is_valid() and not _loading_status[path].callbacks.has(callback):
			_loading_status[path].callbacks.append(callback)
		return true
	
	# Check if path exists
	if not ResourceLoader.exists(path):
		push_error("GameResourceLoader: Failed to load resource - path does not exist: " + path)
		return false
	
	# Start loading
	ResourceLoader.load_threaded_request(path)
	
	# Set up loading status
	_loading_status[path] = {
		"callbacks": [] if not callback.is_valid() else [callback],
		"start_time": Time.get_ticks_msec()
	}
	
	# Start polling in the next frame
	call_deferred("_poll_loading_status", path)
	return true

# Clear cache to free memory
func clear_cache():
	_cache.clear()
	cache_cleared.emit()

# Clear specific resource from cache
func clear_resource(path: String):
	if _cache.has(path):
		_cache.erase(path)

# Check if a resource is cached
func is_cached(path: String) -> bool:
	return _cache.has(path)

# Get the size of the cache
func get_cache_size() -> int:
	return _cache.size()

# Private: Poll the loading status of a resource
func _poll_loading_status(path: String):
	if not _loading_status.has(path):
		return
	
	var status = ResourceLoader.load_threaded_get_status(path)
	
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			var resource = ResourceLoader.load_threaded_get(path)
			_cache[path] = resource
			resource_loaded.emit(path, resource)
			
			# Call callbacks
			for callback in _loading_status[path].callbacks:
				if callback.is_valid():
					callback.call(resource)
			
			# Clean up
			_loading_status.erase(path)
			
		ResourceLoader.THREAD_LOAD_FAILED:
			push_error("GameResourceLoader: Failed to load resource: " + path)
			_loading_status.erase(path)
			
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error("GameResourceLoader: Invalid resource: " + path)
			_loading_status.erase(path)
			
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			# Continue polling
			call_deferred("_poll_loading_status", path)

# Private: Clean up oldest resources when cache is too large
func _cleanup_oldest_resources(count: int = 10):
	var paths = _cache.keys()
	paths.sort_custom(func(a, b): return _cache[a].get_meta("last_accessed", 0) < _cache[b].get_meta("last_accessed", 0))
	
	for i in range(min(count, paths.size())):
		_cache.erase(paths[i])

# Example usage:
# var texture = GameResourceLoader.load_resource("res://assets/sprites/player_ship.png")
# GameResourceLoader.load_resource_async("res://assets/sprites/enemy_ship.png", func(res): print("Loaded:", res))
