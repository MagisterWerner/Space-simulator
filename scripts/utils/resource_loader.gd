# scripts/utils/resource_loader.gd
extends Node
class_name GameResourceLoader

# Centralized resource management with caching
# This prevents redundant loading of the same resources

var _cache = {}

# Preload a resource (compile-time)
func preload_resource(path: String):
	if _cache.has(path):
		return _cache[path]
	
	var resource = preload(path)
	_cache[path] = resource
	return resource

# Load a resource (runtime)
func load_resource(path: String):
	if _cache.has(path):
		return _cache[path]
	
	if ResourceLoader.exists(path):
		var resource = load(path)
		_cache[path] = resource
		return resource
	else:
		push_error("Failed to load resource: " + path)
		return null

# Clear cache to free memory
func clear_cache():
	_cache.clear()

# Clear specific resource from cache
func clear_resource(path: String):
	if _cache.has(path):
		_cache.erase(path)

# Check if a resource is cached
func is_cached(path: String) -> bool:
	return _cache.has(path)

# Example usage in entity_manager.gd:
# Replace:
# player_ship_scene = load("res://player_ship.tscn")
# With:
# player_ship_scene = GameResourceLoader.load_resource("res://scenes/player/player_ship.tscn")
