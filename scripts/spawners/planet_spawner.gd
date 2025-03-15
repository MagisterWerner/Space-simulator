extends EntitySpawner
class_name PlanetSpawner

# Planet-specific configuration
@export_category("Planet Configuration")
@export var terran_planet_scene: String = "res://scenes/world/planet_terran.tscn"
@export var gaseous_planet_scene: String = "res://scenes/world/planet_gaseous.tscn"
@export var moon_scene: String = "res://scenes/world/moon_base.tscn"
@export var rocky_moon_scene: String = "res://scenes/world/moon_rocky.tscn"
@export var icy_moon_scene: String = "res://scenes/world/moon_icy.tscn"
@export var volcanic_moon_scene: String = "res://scenes/world/moon_volcanic.tscn"

# Debug Options
@export var debug_planet_generation: bool = false
@export var debug_moon_orbits: bool = false
@export var debug_orbit_line_width: float = 1.0

# Scene cache for different planet types
var _scene_cache_terran = null
var _scene_cache_gaseous = null
var _moon_scene_cache = {}
var _spawned_moons: Dictionary = {}  # Maps planet_id to array of moons

func _ready() -> void:
	# We don't set scene_path in the base class because we have multiple scenes
	entity_type = "planet"
	
	# Initialize moon scene cache
	_initialize_moon_scenes()
	
	# Load planet scenes
	_load_planet_scenes()

func _load_planet_scenes() -> void:
	# Load terran planet scene
	if ResourceLoader.exists(terran_planet_scene):
		_scene_cache_terran = load(terran_planet_scene)
	else:
		push_error("PlanetSpawner: Terran planet scene not found: " + terran_planet_scene)
	
	# Load gaseous planet scene
	if ResourceLoader.exists(gaseous_planet_scene):
		_scene_cache_gaseous = load(gaseous_planet_scene)
	else:
		push_error("PlanetSpawner: Gaseous planet scene not found: " + gaseous_planet_scene)
	
	if debug_planet_generation:
		print("PlanetSpawner: Planet scenes loaded")

func _initialize_moon_scenes() -> void:
	# Load each moon type scene
	var scenes = {
		MoonData.MoonType.ROCKY: rocky_moon_scene,
		MoonData.MoonType.ICY: icy_moon_scene,
		MoonData.MoonType.VOLCANIC: volcanic_moon_scene
	}
	
	for type in scenes:
		var path = scenes[type]
		if ResourceLoader.exists(path):
			_moon_scene_cache[type] = load(path)
		else:
			# Fallback to base moon scene
			if ResourceLoader.exists(moon_scene):
				_moon_scene_cache[type] = load(moon_scene)
			else:
				push_error("PlanetSpawner: No moon scene available for type: " + str(type))

# Override validation to check planet data
func _validate_entity_data(entity_data) -> bool:
	if not super._validate_entity_data(entity_data):
		return false
	
	# Verify this is a planet
	if not entity_data is PlanetData:
		push_error("PlanetSpawner: Invalid entity data, expected PlanetData but got " + str(entity_data.get_class()))
		return false
	
	return true

# Override to provide specialized planet instantiation
func _get_entity() -> Node:
	# We override this to choose between terran and gaseous planet scenes
	return null  # This will be handled in spawn_entity

# Override spawn_entity to handle planet-specific logic
func spawn_entity(entity_data) -> Node:
	if not _validate_entity_data(entity_data):
		return null
	
	var planet_data: PlanetData = entity_data
	var entity_id = planet_data.entity_id
	
	# Choose the appropriate scene based on planet type
	var scene = _scene_cache_terran if planet_data.planet_category == PlanetData.PlanetCategory.TERRAN else _scene_cache_gaseous
	
	if not scene:
		push_error("PlanetSpawner: No scene available for planet category: " + str(planet_data.planet_category))
		return null
	
	# Instance the planet
	var planet = scene.instantiate()
	add_child(planet)
	
	# Position the planet
	planet.global_position = planet_data.world_position
	
	# Configure the planet
	_configure_planet(planet, planet_data)
	
	# Register with EntityManager if enabled
	if auto_register_with_entity_manager and _entity_manager and _entity_manager.has_method("register_entity"):
		_entity_manager.register_entity(planet, entity_type)
	
	# Track the entity
	_entity_map[entity_id] = planet
	_data_map[entity_id] = planet_data
	
	# Spawn moons if any
	if not planet_data.moons.is_empty():
		_spawn_moons(planet, planet_data)
	
	# Connect to signals
	if not planet.tree_exiting.is_connected(_on_entity_tree_exiting):
		planet.tree_exiting.connect(_on_entity_tree_exiting.bind(planet))
	
	# Emit signal
	entity_spawned.emit(planet, planet_data)
	
	return planet

# Configure a planet with its data
func _configure_planet(planet: Node, planet_data: PlanetData) -> void:
	# Set planet name
	if "planet_name" in planet:
		planet.planet_name = planet_data.entity_name
	
	# Set debug options
	if "debug_draw_orbits" in planet:
		planet.debug_draw_orbits = debug_moon_orbits
	
	if "debug_orbit_line_width" in planet:
		planet.debug_orbit_line_width = debug_orbit_line_width
	
	# Initialize the planet based on its category
	var init_params = {
		"seed_value": planet_data.seed_value,
		"grid_x": planet_data.grid_cell.x,
		"grid_y": planet_data.grid_cell.y,
	}
	
	# Add category-specific parameters
	if planet_data.planet_category == PlanetData.PlanetCategory.TERRAN:
		init_params["theme_override"] = planet_data.planet_theme
		init_params["category_override"] = PlanetData.PlanetCategory.TERRAN
	else:
		init_params["gas_giant_type_override"] = planet_data.planet_theme - PlanetData.PlanetTheme.JUPITER
		init_params["category_override"] = PlanetData.PlanetCategory.GASEOUS
	
	# Apply debug settings
	init_params["debug_draw_orbits"] = debug_moon_orbits
	init_params["debug_orbit_line_width"] = debug_orbit_line_width
	init_params["debug_planet_generation"] = debug_planet_generation
	
	# Initialize the planet
	if planet.has_method("initialize"):
		planet.initialize(init_params)

# Spawn moons for a planet
func _spawn_moons(planet: Node, planet_data: PlanetData) -> void:
	var planet_id = planet_data.entity_id
	_spawned_moons[planet_id] = []
	
	for moon_data in planet_data.moons:
		var moon_type = moon_data.moon_type
		
		# Get the appropriate scene for this moon type
		var moon_scene = _moon_scene_cache.get(moon_type)
		if not moon_scene:
			continue
		
		# Instance the moon
		var moon = moon_scene.instantiate()
		planet.add_child(moon)
		
		# Configure the moon
		_configure_moon(moon, moon_data, planet)
		
		# Track the moon
		_spawned_moons[planet_id].append(moon)
		
		# Register with EntityManager if needed
		if auto_register_with_entity_manager and _entity_manager and _entity_manager.has_method("register_entity"):
			_entity_manager.register_entity(moon, "moon")

# Configure a moon with its data
func _configure_moon(moon: Node, moon_data: MoonData, parent_planet: Node) -> void:
	# Create the initialization parameters
	var moon_params = {
		"seed_value": moon_data.seed_value,
		"parent_planet": parent_planet,
		"distance": moon_data.orbit_distance,
		"base_angle": moon_data.base_angle,
		"orbit_speed": moon_data.orbit_speed,
		"orbit_deviation": moon_data.orbit_deviation,
		"phase_offset": moon_data.phase_offset,
		"parent_name": parent_planet.name if "name" in parent_planet else "Planet",
		"moon_name": moon_data.entity_name,
		"moon_type": moon_data.moon_type,
		"orbital_inclination": moon_data.orbital_inclination,
		"orbit_vertical_offset": moon_data.orbit_vertical_offset,
		"is_gaseous": moon_data.is_gaseous
	}
	
	# Initialize the moon
	if moon.has_method("initialize"):
		moon.initialize(moon_params)

# Override despawn to handle moons
func despawn_entity(entity_id: int) -> void:
	if not _entity_map.has(entity_id):
		return
	
	var planet = _entity_map[entity_id]
	var planet_data = _data_map[entity_id]
	
	# Despawn any moons first
	if _spawned_moons.has(entity_id):
		var moons = _spawned_moons[entity_id]
		for moon in moons:
			if is_instance_valid(moon):
				# Deregister moon from entity manager
				if auto_register_with_entity_manager and _entity_manager and _entity_manager.has_method("deregister_entity"):
					_entity_manager.deregister_entity(moon)
				
				# Queue moon for deletion
				moon.queue_free()
		
		_spawned_moons.erase(entity_id)
	
	# Now handle the planet itself
	
	# Deregister with EntityManager
	if auto_register_with_entity_manager and _entity_manager and _entity_manager.has_method("deregister_entity"):
		_entity_manager.deregister_entity(planet)
	
	# Emit signal
	entity_despawned.emit(planet, planet_data)
	
	# Remove from tracking
	_entity_map.erase(entity_id)
	_data_map.erase(entity_id)
	
	# Return to pool or free
	_return_entity_to_pool(planet)
