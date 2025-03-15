# scripts/spawners/planet_spawner.gd
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
		
		# Initialize the planet
		planet.initialize(params)
	
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
		moon.initialize(params)
	
	# Register with entity manager
	register_entity(moon, "moon", moon_data)
	
	return moon

# Utility function to create a planet at a specific grid cell
func spawn_planet_at_cell(cell: Vector2i, is_gaseous: bool = false, theme_id: int = -1) -> Node:
	# Create a new PlanetData object
	var entity_id = 1
	if _entity_manager and _entity_manager.has_method("get_next_entity_id"):
		entity_id = _entity_manager.get_next_entity_id()
	
	# Calculate world position from cell
	var position = _get_cell_world_position(cell)
	
	# Create appropriate seed
	var seed_value = 0
	if _game_settings:
		var base_seed = _game_settings.get_seed()
		seed_value = base_seed + (cell.x * 1000) + (cell.y * 100)
	
	# Create planet data
	var planet_data = PlanetData.new(entity_id, position, seed_value, theme_id)
	planet_data.is_gaseous = is_gaseous
	planet_data.grid_cell = cell
	
	# Generate a name for the planet
	planet_data.planet_name = planet_data.generate_name()
	
	# Spawn the planet
	return spawn_planet(planet_data)
