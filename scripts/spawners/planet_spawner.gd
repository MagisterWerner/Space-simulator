extends EntitySpawnerBase
class_name PlanetSpawner

# Scene paths
const TERRAN_PLANET_SCENE = "res://scenes/world/planet_terran.tscn"
const GASEOUS_PLANET_SCENE = "res://scenes/world/planet_gaseous.tscn"
const MOON_SCENE_BASE = "res://scenes/world/moon_base.tscn"
const MOON_SCENE_ROCKY = "res://scenes/world/moon_rocky.tscn"
const MOON_SCENE_ICY = "res://scenes/world/moon_icy.tscn"
const MOON_SCENE_VOLCANIC = "res://scenes/world/moon_volcanic.tscn"

# Moon type mapping for scene selection
var _moon_scenes = {}

# Cache for planets and their moons
var _planet_cache = {}

# Texture generator (only used if planet textures aren't provided)
var _texture_generator = null

func _load_common_scenes() -> void:
	# Load planet scenes
	_load_scene("planet_terran", TERRAN_PLANET_SCENE)
	_load_scene("planet_gaseous", GASEOUS_PLANET_SCENE)
	
	# Load moon scenes if they exist
	_load_scene("moon_base", MOON_SCENE_BASE)
	_load_scene("moon_rocky", MOON_SCENE_ROCKY)
	_load_scene("moon_icy", MOON_SCENE_ICY)
	_load_scene("moon_volcanic", MOON_SCENE_VOLCANIC)
	
	# Map moon types to scene keys
	_moon_scenes[MoonData.MoonType.ROCKY] = "moon_rocky"
	_moon_scenes[MoonData.MoonType.ICY] = "moon_icy"
	_moon_scenes[MoonData.MoonType.VOLCANIC] = "moon_volcanic"
	
	# Initialize texture generator if needed for fallback
	_texture_generator = load("res://scripts/generators/planet_generator_base.gd").new()
	add_child(_texture_generator)

func spawn_entity(data: EntityData) -> Node:
	if not _initialized:
		await spawner_ready
	
	if data is PlanetData:
		return spawn_planet(data)
	elif data is MoonData:
		return spawn_moon(data)
	
	push_error("PlanetSpawner: Unknown data type for spawning")
	return null

func spawn_planet(planet_data: PlanetData) -> Node:
	# Determine scene based on planet category
	var scene_key = "planet_gaseous" if planet_data.is_gaseous else "planet_terran"
	
	if not _scene_cache.has(scene_key):
		push_error("PlanetSpawner: Missing scene: " + scene_key)
		return null
	
	# Instantiate the planet
	var planet = _scene_cache[scene_key].instantiate()
	add_child(planet)
	
	# Set position
	planet.global_position = planet_data.position
	
	# Configure the planet
	if planet.has_method("initialize"):
		var params = {
			"seed_value": planet_data.seed_value,
			"theme_override": planet_data.planet_theme,
			"category_override": planet_data.planet_category,
			"use_texture_cache": true,
			"debug_planet_generation": _debug_mode
		}
		
		# Add grid position if available
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
	
	# Keep track of this planet in our cache
	_planet_cache[planet_data.entity_id] = planet
	
	# Register with entity manager
	register_entity(planet, "planet", planet_data)
	
	# Spawn all associated moons
	for moon_data in planet_data.moons:
		spawn_moon(moon_data, planet)
	
	return planet

func spawn_moon(moon_data: MoonData, parent_planet = null) -> Node:
	# Find parent planet if not provided
	if parent_planet == null and moon_data.parent_planet_id > 0:
		parent_planet = _planet_cache.get(moon_data.parent_planet_id)
		
		# If still not found, look for it in the entity manager
		if parent_planet == null and _entity_manager:
			parent_planet = _entity_manager.get_entity_by_id(moon_data.parent_planet_id)
	
	# Can't spawn a moon without a parent
	if parent_planet == null:
		push_error("PlanetSpawner: Cannot spawn moon without parent planet")
		return null
	
	# Get the appropriate scene key for this moon type
	var scene_key = _moon_scenes.get(moon_data.moon_type, "moon_base")
	if not _scene_cache.has(scene_key):
		# Fall back to base moon scene
		scene_key = "moon_base"
		if not _scene_cache.has(scene_key):
			push_error("PlanetSpawner: No moon scenes available")
			return null
	
	# Instantiate the moon
	var moon = _scene_cache[scene_key].instantiate()
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
