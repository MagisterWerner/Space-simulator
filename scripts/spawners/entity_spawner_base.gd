# scripts/spawners/entity_spawner_base.gd
# Base class for all entity spawners - focused only on instantiation, not generation
extends Node
class_name EntitySpawnerBase

signal entity_spawned(entity, data)

# Scene cache - optimized by storing just PackedScene references
var scene_cache: Dictionary = {}

# Manager references - properly encapsulated
var _entity_manager = null
var _content_registry = null
var _debug_mode: bool = false

# Track spawned entities for better cleanup
var _spawned_entities: Array = []

func _ready() -> void:
	# Add to spawner group
	add_to_group("spawners")
	
	# Find dependencies
	_entity_manager = get_node_or_null("/root/EntityManager")
	_content_registry = get_node_or_null("/root/ContentRegistry")
	
	# Check debug mode
	var game_settings = get_tree().current_scene.get_node_or_null("GameSettings")
	if game_settings:
		_debug_mode = game_settings.debug_mode
	
	# Load all common resources
	_load_resources()

# Virtual method for loading resources, overridden by subclasses
func _load_resources() -> void:
	pass

# Load a scene into cache
func _load_scene(key: String, path: String) -> void:
	if scene_cache.has(key):
		return
	
	if ResourceLoader.exists(path):
		scene_cache[key] = load(path)
	else:
		push_error("EntitySpawnerBase: Scene not found: " + path)

# Spawn an entity from its data
func spawn_entity(entity_data: EntityData) -> Node:
	# This is a virtual method to be overridden by subclasses
	push_error("EntitySpawnerBase: spawn_entity is a virtual method that should be overridden")
	return null

# Register a spawned entity with entity manager
func register_entity(entity: Node, entity_type: String, data = null) -> void:
	if _entity_manager and _entity_manager.has_method("register_entity"):
		_entity_manager.register_entity(entity, entity_type)
	
	# Track for cleanup
	if not _spawned_entities.has(entity):
		_spawned_entities.append(entity)
	
	# Emit signal
	entity_spawned.emit(entity, data)

# Despawn an entity
func despawn_entity(entity: Node) -> void:
	if not is_instance_valid(entity):
		return
	
	# Deregister from entity manager
	if _entity_manager and _entity_manager.has_method("deregister_entity"):
		_entity_manager.deregister_entity(entity)
	
	# Remove from tracking
	if _spawned_entities.has(entity):
		_spawned_entities.erase(entity)
	
	# Queue for deletion
	entity.queue_free()

# Clean up all spawned entities
func clear_all_entities() -> void:
	var entities_to_clean = _spawned_entities.duplicate()
	for entity in entities_to_clean:
		if is_instance_valid(entity):
			despawn_entity(entity)
	_spawned_entities.clear()

# Helper to check if an object has a property
func has_property(obj: Object, property_name: String) -> bool:
	for property in obj.get_property_list():
		if property.name == property_name:
			return true
	return false


# scripts/spawners/asteroid_spawner.gd
# Spawner for asteroids and asteroid fields - now focuses only on instantiation
extends EntitySpawnerBase
class_name AsteroidSpawner

# Scene paths
const ASTEROID_SCENE = "res://scenes/entities/asteroid.tscn"
const ASTEROID_FIELD_SCENE = "res://scenes/world/asteroid_field.tscn"

func _load_resources() -> void:
	_load_scene("asteroid", ASTEROID_SCENE)
	_load_scene("asteroid_field", ASTEROID_FIELD_SCENE)

func spawn_entity(entity_data: EntityData) -> Node:
	if entity_data is AsteroidData:
		return spawn_asteroid(entity_data)
	elif entity_data is AsteroidFieldData:
		return spawn_asteroid_field(entity_data)
	
	push_error("AsteroidSpawner: Unknown entity data type")
	return null

func spawn_asteroid(asteroid_data: AsteroidData) -> Node:
	if not scene_cache.has("asteroid"):
		push_error("AsteroidSpawner: Asteroid scene not loaded")
		return null
	
	# Instantiate asteroid
	var asteroid = scene_cache["asteroid"].instantiate()
	add_child(asteroid)
	
	# Set position
	asteroid.global_position = asteroid_data.position
	
	# Get size string
	var size_string = "medium"
	match asteroid_data.size_category:
		AsteroidData.SizeCategory.SMALL: size_string = "small"
		AsteroidData.SizeCategory.MEDIUM: size_string = "medium" 
		AsteroidData.SizeCategory.LARGE: size_string = "large"
	
	# Get texture from content registry
	if _content_registry and asteroid.get_node_or_null("Sprite2D"):
		var texture = _content_registry.get_asteroid_texture(asteroid_data)
		if texture:
			asteroid.get_node("Sprite2D").texture = texture
	
	# Configure the asteroid
	if asteroid.has_method("setup"):
		asteroid.setup(
			size_string,
			asteroid_data.variant,
			asteroid_data.scale_factor,
			asteroid_data.rotation_speed,
			asteroid_data.linear_velocity
		)
	
	# Register with entity manager
	register_entity(asteroid, "asteroid", asteroid_data)
	
	return asteroid

func spawn_asteroid_field(field_data: AsteroidFieldData) -> Node:
	var field
	
	if scene_cache.has("asteroid_field"):
		# Use the proper scene
		field = scene_cache["asteroid_field"].instantiate()
	else:
		# Create a simple container as fallback
		field = Node2D.new()
	
	field.name = "AsteroidField_" + str(field_data.entity_id)
	add_child(field)
	
	# Set position
	field.global_position = field_data.position
	
	# Configure field properties if available
	if has_property(field, "field_radius"):
		field.field_radius = field_data.field_radius
	
	if has_property(field, "min_asteroids"):
		field.min_asteroids = field_data.min_asteroids
	
	if has_property(field, "max_asteroids"):
		field.max_asteroids = field_data.max_asteroids
	
	# Spawn all asteroids in the field
	for asteroid_data in field_data.asteroids:
		var asteroid = spawn_asteroid(asteroid_data)
		if asteroid:
			# Move to field and adjust position to be relative
			remove_child(asteroid)
			field.add_child(asteroid)
			asteroid.position = asteroid_data.position - field_data.position
	
	# Register field with entity manager
	register_entity(field, "asteroid_field", field_data)
	
	return field


# scripts/spawners/planet_spawner.gd
# Spawner for planets and moons - now focuses only on instantiation
extends EntitySpawnerBase
class_name PlanetSpawner

# Scene paths
const TERRAN_PLANET_SCENE = "res://scenes/world/planet_terran.tscn"
const GASEOUS_PLANET_SCENE = "res://scenes/world/planet_gaseous.tscn"
const MOON_SCENE_BASE = "res://scenes/world/moon_base.tscn"
const MOON_SCENE_ROCKY = "res://scenes/world/moon_rocky.tscn"
const MOON_SCENE_ICY = "res://scenes/world/moon_icy.tscn"
const MOON_SCENE_VOLCANIC = "res://scenes/world/moon_volcanic.tscn"

# Mapping of moon types to scene keys
var _moon_type_to_scene = {
	MoonData.MoonType.ROCKY: "moon_rocky",
	MoonData.MoonType.ICY: "moon_icy",
	MoonData.MoonType.VOLCANIC: "moon_volcanic"
}

# Reference to spawned planets - only used internally for moon parenting
var _spawned_planets = {}

func _load_resources() -> void:
	_load_scene("planet_terran", TERRAN_PLANET_SCENE)
	_load_scene("planet_gaseous", GASEOUS_PLANET_SCENE)
	_load_scene("moon_base", MOON_SCENE_BASE)
	_load_scene("moon_rocky", MOON_SCENE_ROCKY)
	_load_scene("moon_icy", MOON_SCENE_ICY)
	_load_scene("moon_volcanic", MOON_SCENE_VOLCANIC)

func spawn_entity(entity_data: EntityData) -> Node:
	if entity_data is PlanetData:
		return spawn_planet(entity_data)
	elif entity_data is MoonData:
		return spawn_moon(entity_data)
	
	push_error("PlanetSpawner: Unknown entity data type")
	return null

func spawn_planet(planet_data: PlanetData) -> Node:
	# Determine which scene to use
	var scene_key = "planet_gaseous" if planet_data.is_gaseous else "planet_terran"
	
	if not scene_cache.has(scene_key):
		push_error("PlanetSpawner: Planet scene not loaded: " + scene_key)
		return null
	
	# Instantiate planet
	var planet = scene_cache[scene_key].instantiate()
	add_child(planet)
	
	# Set position
	planet.global_position = planet_data.position
	
	# Configure through initialize method if available
	if planet.has_method("initialize"):
		# Get texture from content registry - key optimization
		var atmosphere_data = {}
		var params = {
			"seed_value": planet_data.seed_value,
			"theme_override": planet_data.planet_theme,
			"category_override": planet_data.planet_category,
			"use_texture_cache": true,
			"debug_planet_generation": _debug_mode
		}
		
		# Add grid cell if available
		if planet_data.grid_cell != Vector2i(-1, -1):
			params["grid_x"] = planet_data.grid_cell.x
			params["grid_y"] = planet_data.grid_cell.y
		
		# Add atmosphere data if available
		if not planet_data.atmosphere_data.is_empty():
			params["atmosphere_data"] = planet_data.atmosphere_data
		
		# Add name if available
		if not planet_data.planet_name.is_empty():
			params["planet_name"] = planet_data.planet_name
		
		# Initialize the planet
		planet.initialize(params)
	else:
		# Set basic properties for simpler planets
		if has_property(planet, "planet_name") and not planet_data.planet_name.is_empty():
			planet.planet_name = planet_data.planet_name
			
		if has_property(planet, "planet_theme"):
			planet.planet_theme = planet_data.planet_theme
	
	# Track the planet
	_spawned_planets[planet_data.entity_id] = planet
	
	# Register with entity manager
	register_entity(planet, "planet", planet_data)
	
	# Spawn moons if this is the first time spawning
	if not _spawned_entities.has(planet):
		for moon_data in planet_data.moons:
			spawn_moon(moon_data, planet)
	
	return planet

func spawn_moon(moon_data: MoonData, parent_planet = null) -> Node:
	# Find parent planet if not provided
	if parent_planet == null and moon_data.parent_planet_id > 0:
		parent_planet = _spawned_planets.get(moon_data.parent_planet_id)
		
		if parent_planet == null and _entity_manager:
			parent_planet = _entity_manager.get_entity_by_id(moon_data.parent_planet_id)
	
	if parent_planet == null:
		push_error("PlanetSpawner: Cannot spawn moon without parent planet")
		return null
	
	# Get the appropriate scene for this moon type
	var scene_key = _moon_type_to_scene.get(moon_data.moon_type, "moon_base")
	if not scene_cache.has(scene_key):
		scene_key = "moon_base"
		if not scene_cache.has(scene_key):
			push_error("PlanetSpawner: No moon scene available")
			return null
	
	# Instantiate the moon
	var moon = scene_cache[scene_key].instantiate()
	parent_planet.add_child(moon)
	
	# Configure the moon
	if moon.has_method("initialize"):
		var params = {
			"seed_value": moon_data.seed_value,
			"parent_planet": parent_planet,
			"distance": moon_data.distance,
			"base_angle": moon_data.base_angle,
			"orbit_speed": moon_data.orbit_speed,
			"orbit_deviation": moon_data.orbit_deviation,
			"phase_offset": moon_data.phase_offset,
			"moon_name": moon_data.moon_name,
			"use_texture_cache": true,
			"is_gaseous": moon_data.is_gaseous,
			"moon_type": moon_data.moon_type,
			"orbital_inclination": moon_data.orbital_inclination,
			"orbit_vertical_offset": moon_data.orbit_vertical_offset
		}
		
		# Set orbit colors if available
		if moon_data.orbit_color != Color.WHITE:
			params["orbit_color"] = moon_data.orbit_color
			
		if moon_data.indicator_color != Color.WHITE:
			params["indicator_color"] = moon_data.indicator_color
			
		moon.initialize(params)
	else:
		# Set basic properties for simpler moons
		if has_property(moon, "moon_name") and not moon_data.moon_name.is_empty():
			moon.moon_name = moon_data.moon_name
			
		if has_property(moon, "orbit_speed"):
			moon.orbit_speed = moon_data.orbit_speed
			
		if has_property(moon, "distance"):
			moon.distance = moon_data.distance
	
	# Register with entity manager
	register_entity(moon, "moon", moon_data)
	
	return moon


# scripts/spawners/spawner_manager.gd
# Centralized manager for all entity spawners
extends Node
class_name SpawnerManager

signal spawner_ready(spawner_type)
signal entity_spawned(entity, entity_type, data)

# Spawner references
var planet_spawner: PlanetSpawner
var asteroid_spawner: AsteroidSpawner
var fragment_spawner: FragmentSpawner

# Content registry reference
var _content_registry: ContentRegistry = null

# Track spawners
var _spawners = {}
var _debug_mode: bool = false

func _ready() -> void:
	# Add to spawner_managers group
	add_to_group("spawner_managers")
	
	# Find content registry
	_content_registry = get_node_or_null("/root/ContentRegistry")
	
	# Check debug mode
	var game_settings = get_tree().current_scene.get_node_or_null("GameSettings")
	if game_settings:
		_debug_mode = game_settings.debug_mode
	
	# Create spawners
	_create_spawners()
	
	# Connect to spawner signals
	for spawner_name in _spawners:
		var spawner = _spawners[spawner_name]
		if spawner.has_signal("entity_spawned") and not spawner.is_connected("entity_spawned", _on_entity_spawned):
			spawner.connect("entity_spawned", _on_entity_spawned)

# Create all spawners
func _create_spawners() -> void:
	# Create planet spawner
	planet_spawner = PlanetSpawner.new()
	planet_spawner.name = "PlanetSpawner"
	add_child(planet_spawner)
	_spawners["planet"] = planet_spawner
	
	# Create asteroid spawner
	asteroid_spawner = AsteroidSpawner.new()
	asteroid_spawner.name = "AsteroidSpawner"
	add_child(asteroid_spawner)
	_spawners["asteroid"] = asteroid_spawner
	
	# Create fragment spawner
	fragment_spawner = FragmentSpawner.new()
	fragment_spawner.name = "FragmentSpawner"
	add_child(fragment_spawner)
	_spawners["fragment"] = fragment_spawner
	
	# Emit ready signal
	for spawner_type in _spawners:
		spawner_ready.emit(spawner_type)

# Main API: Spawn any entity from data
func spawn_entity(entity_data: EntityData) -> Node:
	# Route to appropriate spawner based on entity type
	if entity_data is PlanetData or entity_data is MoonData:
		return planet_spawner.spawn_entity(entity_data)
	elif entity_data is AsteroidData or entity_data is AsteroidFieldData:
		return asteroid_spawner.spawn_entity(entity_data)
	else:
		push_error("SpawnerManager: Unknown entity data type")
		return null

# Handle entity spawned event
func _on_entity_spawned(entity: Node, data) -> void:
	# Determine entity type
	var entity_type = "unknown"
	
	if data is PlanetData:
		entity_type = "planet"
	elif data is MoonData:
		entity_type = "moon"
	elif data is AsteroidData:
		entity_type = "asteroid"
	elif data is AsteroidFieldData:
		entity_type = "asteroid_field"
	
	# Emit our own signal
	entity_spawned.emit(entity, entity_type, data)

# Clear all entities
func clear_all_entities() -> void:
	for spawner_name in _spawners:
		_spawners[spawner_name].clear_all_entities()
